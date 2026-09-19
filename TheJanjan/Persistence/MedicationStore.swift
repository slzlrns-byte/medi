import Foundation
import OSLog
import SwiftData
import JanjanCore

/// 약과 그 딸린 기록을 함께 다루는 곳.
///
/// CloudKit 제약 때문에 이 앱에는 SwiftData 관계가 없다 — 전부 UUID 외래키다.
/// 그래서 **연쇄 삭제도 없다.** 약만 지우면 스케줄·복용 기록·재고 사건이
/// 주인 없이 남아 재고 계산에 계속 끼어든다. 지우는 일을 여기 한 곳에 모으는 이유다.
@MainActor
enum MedicationStore {

    private static let logger = Logger(subsystem: Janjan.appBundleID, category: "medication-store")

    /// 등록 화면이 채워서 넘기는 초안.
    struct Draft {
        var medication: Medication
        var schedules: [Schedule]
        /// 처음에 세어 본 개수. nil 이면 재고를 쓰지 않는다는 뜻이다.
        var initialStock: Decimal?
    }

    /// 새 약 하나와 그 스케줄·초기 재고를 함께 저장한다.
    @discardableResult
    static func add(_ draft: Draft, at moment: Date = Date(), in context: ModelContext) -> UUID {
        context.insert(MedicationRecord.make(from: draft.medication))

        for schedule in draft.schedules {
            context.insert(ScheduleRecord.make(from: schedule))
        }

        // 첫 재고는 보충이 아니라 **직접 정정**으로 넣는다.
        // 정정은 기준점을 세우므로, 나중에 다시 세어 고쳐도 이전 계산이 따라오지 않는다(설계 05절).
        if let stock = draft.initialStock {
            let event = StockEvent.correction(
                medicationID: draft.medication.id,
                setTo: stock,
                at: moment,
                note: "등록할 때 세어 둔 개수"
            )
            context.insert(StockEventRecord.make(from: event))
        }

        save("약 등록", in: context)
        return draft.medication.id
    }

    /// 등록한 약을 고칠 때 넘기는 값.
    ///
    /// 재고는 여기 없다. 재고는 "세어 본 사건" 이 쌓여 만들어지는 값이라
    /// (설계 05절) 폼의 숫자 하나로 덮으면 기준점이 끊긴다. 다시 세는 일은
    /// 상세 화면의 "다시 세기" 가 맡는다.
    struct Edit {
        var name: String
        var strengthText: String
        var form: Medication.Form
        var kind: Medication.Kind
        var purposeLine: String
        var schedules: [Schedule]
    }

    /// 등록한 약을 **제자리에서** 고친다.
    ///
    /// 약 기록을 지우고 새로 만들지 않는다. id 가 그대로라야 지난 복용·재고·
    /// 메모·처방이 이 약에 계속 붙어 있는다 - 관계 없는 스키마라(위 주석)
    /// 아무도 대신 이어 주지 않고, 새 id 로 갈아 끼우면 그 약의 과거가 통째로
    /// 주인을 잃는다.
    ///
    /// 시간대는 통째로 다시 깐다. 복용 기록은 스케줄 id 가 아니라 약 id 와
    /// 시각으로 매여 있어(DoseEvent), 줄을 새로 깔아도 지난 기록은 그대로다.
    static func update(_ edit: Edit, for medicationID: UUID, in context: ModelContext) {
        guard let record = medicationRecord(medicationID, in: context) else {
            logger.error("없는 약을 고치려 했습니다.")
            return
        }

        record.name = edit.name
        record.strengthText = edit.strengthText
        record.formRaw = edit.form.rawValue
        record.kindRaw = edit.kind.rawValue
        record.purposeLine = edit.purposeLine

        // 이미 잠금화면에 떠 있는 알림은 고치기 전의 이름과 시각을 말하고 있다.
        // 남겨 두면 옛 이름이 계속 보이고, 거기서 누른 답이 옛 시간대로 들어간다.
        NotificationManager.shared.removeDeliveredNotifications(for: medicationID)

        delete(FetchDescriptor<ScheduleRecord>(
            predicate: #Predicate { $0.medicationID == medicationID }
        ), in: context)

        for schedule in edit.schedules {
            context.insert(ScheduleRecord.make(from: schedule))
        }

        save("약 수정", in: context)
    }

    /// 진료에서 들은 용량 변경을 **적어 두고 동시에 적용한다.**
    ///
    /// 용량 변경은 지금까지 적어 두기만 했다(강점 결정서 D12). 그것은 앱이
    /// 해석을 하지 않는다는 뜻이지, 옛 숫자로 계속 계산한다는 뜻이 아니었다 -
    /// 1회 개수가 1정에서 2정이 되면 재고도 소진 예측도 그때부터 달라져야 한다.
    /// 그래서 사건은 그대로 남기고(DoseChange), 약의 현재 값도 함께 옮긴다.
    ///
    /// - Parameters:
    ///   - newStrengthText: 비었거나 nil 이면 표기는 건드리지 않는다.
    ///   - newDosePerIntake: nil 이면 개수는 건드리지 않는다. 값이 오면 이 약의
    ///     **모든 시간대**에 같은 개수를 넣는다 - 시간대마다 개수가 다른 약은
    ///     화면에서 이 길을 막고 "약 고치기" 로 보낸다.
    /// - Returns: 이력에 남긴 사건. 표기가 그대로면 nil 이다(개수만 바뀐 경우
    ///   "10mg → 10mg" 이라는 빈 화살표가 이력에 쌓이지 않게 한다).
    @discardableResult
    static func applyDoseChange(
        medicationID: UUID,
        newStrengthText: String?,
        newDosePerIntake: Decimal?,
        changedAt: Date,
        note: String? = nil,
        in context: ModelContext
    ) -> DoseChange? {
        guard let record = medicationRecord(medicationID, in: context) else {
            logger.error("없는 약의 용량을 바꾸려 했습니다.")
            return nil
        }

        let fromText = record.strengthText
        let trimmed = newStrengthText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let toText = trimmed.isEmpty ? nil : trimmed

        if let toText { record.strengthText = toText }

        if let dose = newDosePerIntake {
            let descriptor = FetchDescriptor<ScheduleRecord>(
                predicate: #Predicate { $0.medicationID == medicationID }
            )
            for schedule in (try? context.fetch(descriptor)) ?? [] {
                schedule.dosePerIntake = DecimalQuantity.snapToQuarter(dose)
            }
        }

        guard let toText, toText != fromText else {
            save("용량 적용", in: context)
            return nil
        }

        let change = DoseChange(
            medicationID: medicationID,
            // 저장 규칙은 화면에 기대지 않는다 - 아직 오지 않은 날의 용량은 모른다.
            changedAt: min(changedAt, Date()),
            fromText: fromText,
            toText: toText,
            note: note
        )
        context.insert(DoseChangeRecord.make(from: change))
        save("용량 변경 적용", in: context)
        return change
    }

    /// 한 번의 진료로 받아 온 처방과, 그때 채운 약들을 함께 저장한다.
    ///
    /// 보충은 **정정이 아니라 refill** 이다. 정정은 기준점을 새로 세워 그 이전을 지워 버리지만,
    /// 처방은 있던 것 위에 더해지는 사건이라서다(설계 05절).
    ///
    /// `leftovers` 는 진료일에 세어 둔 "받기 전 남아 있던 개수". 이것은 **정정**으로
    /// 넣는다 - 같은 시각의 사건은 정정 → 보충 순서로 계산되므로(InventoryCalculator),
    /// 진료일의 잔여가 기준점이 되고 그 위에 보충이 얹힌다.
    @discardableResult
    static func add(
        prescription: Prescription,
        refills: [(medicationID: UUID, quantity: Decimal)],
        leftovers: [(medicationID: UUID, count: Decimal)] = [],
        at moment: Date = Date(),
        in context: ModelContext
    ) -> UUID {

        context.insert(PrescriptionRecord.make(from: prescription))

        for leftover in leftovers {
            let event = StockEvent.correction(
                medicationID: leftover.medicationID,
                setTo: max(leftover.count, 0),
                at: moment,
                note: "진료일에 세어 둔 개수"
            )
            context.insert(StockEventRecord.make(from: event))
        }

        for refill in refills where refill.quantity > 0 {
            let event = StockEvent.refill(
                medicationID: refill.medicationID,
                quantity: refill.quantity,
                at: moment,
                prescriptionID: prescription.id
            )
            context.insert(StockEventRecord.make(from: event))
        }

        save("처방 기록", in: context)
        return prescription.id
    }

    /// 복용 중 ↔ 중단. 기록은 그대로 두고 앞으로의 일정에서만 뺀다.
    static func setStatus(_ status: Medication.Status, for medicationID: UUID, in context: ModelContext) {
        guard let record = medicationRecord(medicationID, in: context) else { return }
        record.statusRaw = status.rawValue
        // 중단 시각을 남긴다 - "기록 없이 지나간 시간대" 가 중단 전과 후를 가른다.
        // 다시 복용으로 돌아와도 stoppedAt 은 지우지 않는다. resumedAt 과 짝을 이뤄
        // 쉬었던 구간 [stoppedAt, resumedAt) 을 남겨야, 그 사이의 침묵을
        // 빠트림으로 다시 묻지 않는다.
        if status == .stopped {
            record.stoppedAt = Date()
            record.resumedAt = nil
        } else if record.stoppedAt != nil {
            record.resumedAt = Date()
        }
        save("복용 상태 변경", in: context)
    }

    /// 약과 그에 딸린 모든 줄을 지운다. 되돌릴 수 없다.
    static func delete(medicationID: UUID, in context: ModelContext) {
        // 이미 잠금화면에 떠 있는 알림부터 걷는다.
        // 남겨 두면 지운 약의 이름이 계속 보이고, 거기서 "복용함" 을 누르면
        // 주인 없는 복용 기록이 새로 생겨 복약률에 조용히 섞인다.
        NotificationManager.shared.removeDeliveredNotifications(for: medicationID)

        if let record = medicationRecord(medicationID, in: context) {
            context.delete(record)
        }

        delete(FetchDescriptor<ScheduleRecord>(
            predicate: #Predicate { $0.medicationID == medicationID }
        ), in: context)

        delete(FetchDescriptor<DoseEventRecord>(
            predicate: #Predicate { $0.medicationID == medicationID }
        ), in: context)

        delete(FetchDescriptor<StockEventRecord>(
            predicate: #Predicate { $0.medicationID == medicationID }
        ), in: context)

        delete(FetchDescriptor<MedicationNoteRecord>(
            predicate: #Predicate { $0.medicationID == medicationID }
        ), in: context)

        delete(FetchDescriptor<DoseChangeRecord>(
            predicate: #Predicate { $0.medicationID == medicationID }
        ), in: context)

        // 이 약을 가리키던 다른 줄의 손가락도 내려 준다. 관계가 없는 스키마라
        // 아무도 대신 해 주지 않고, 남겨 두면 없는 약을 가리키는 UUID 가 떠돈다.
        let symptoms = FetchDescriptor<SymptomEntryRecord>(
            predicate: #Predicate { $0.relatedMedicationID == medicationID }
        )
        for entry in (try? context.fetch(symptoms)) ?? [] {
            entry.relatedMedicationID = nil
        }

        let idText = medicationID.uuidString
        let prescriptions = FetchDescriptor<PrescriptionRecord>(
            predicate: #Predicate { $0.medicationIDValues.contains(idText) }
        )
        for prescription in (try? context.fetch(prescriptions)) ?? [] {
            prescription.medicationIDValues.removeAll { $0 == idText }
        }

        save("약 삭제", in: context)
    }

    /// 저장된 기록을 전부 지운다. 설정의 "모든 기록 삭제" 가 쓴다.
    ///
    /// iCloud 를 쓰는 중이라면 이 삭제는 동기화를 타고 다른 기기에서도 사라진다.
    /// 화면에서 반드시 그 사실을 먼저 알리고 부른다.
    static func deleteEverything(in context: ModelContext) {
        // 타입을 하나씩 적는다. `JanjanSchema.allModels` 를 돌리고 싶지만
        // `delete(model:)` 는 제네릭이라 `any PersistentModel.Type` 로는 부를 수 없다.
        // 새 모델을 만들면 여기에도 한 줄 늘려야 한다 — 아래 개수 확인이 그걸 잡아 준다.
        // assert 는 릴리스에서 통째로 빠진다. 여기서 빠지면 "모두 사라집니다" 라고
        // 적어 놓고 한 종류를 남겨 두는 일이 앱스토어 빌드에서만 조용히 일어난다.
        precondition(
            JanjanSchema.allModels.count == 9,
            "모델을 추가했다면 전체 삭제에도 넣어 주세요."
        )

        wipe(MedicationRecord.self, in: context)
        wipe(ScheduleRecord.self, in: context)
        wipe(DoseEventRecord.self, in: context)
        wipe(StockEventRecord.self, in: context)
        wipe(CheckInRecord.self, in: context)
        wipe(SymptomEntryRecord.self, in: context)
        wipe(PrescriptionRecord.self, in: context)
        wipe(MedicationNoteRecord.self, in: context)
        wipe(DoseChangeRecord.self, in: context)

        save("전체 삭제", in: context)
    }

    // MARK: - 조각

    private static func wipe<T: PersistentModel>(_ model: T.Type, in context: ModelContext) {
        do {
            try context.delete(model: model)
        } catch {
            logger.error(
                "전체 삭제 실패: \(String(describing: model), privacy: .public) — \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func medicationRecord(_ id: UUID, in context: ModelContext) -> MedicationRecord? {
        var descriptor = FetchDescriptor<MedicationRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func delete<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        in context: ModelContext
    ) {
        guard let rows = try? context.fetch(descriptor) else { return }
        for row in rows { context.delete(row) }
    }

    private static func save(_ what: String, in context: ModelContext) {
        do {
            try context.save()
        } catch {
            logger.error("\(what, privacy: .public) 저장 실패: \(error.localizedDescription, privacy: .public)")
        }
    }
}
