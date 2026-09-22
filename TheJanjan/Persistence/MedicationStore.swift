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
    ///
    /// **재고는 들어 있지 않다**(사용자 결정 2026-09-22). 재고의 기준점은
    /// 진료 기록 한 곳에서만 선다 - 등록에서도 받으면 그 정정 위에 진료
    /// 보충이 얹혀 개수가 두 배가 된다.
    struct Draft {
        var medication: Medication
        var schedules: [Schedule]
    }

    /// 새 약 하나와 그 스케줄을 저장한다.
    @discardableResult
    static func add(_ draft: Draft, in context: ModelContext) -> UUID {
        context.insert(MedicationRecord.make(from: draft.medication))

        for schedule in draft.schedules {
            context.insert(ScheduleRecord.make(from: schedule))
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
        /// 저장 키가 옮겨진 시간대(옛 키 → 새 키).
        ///
        /// 직접 넣은 시간대는 시각이 곧 키다("custom-14:30"). 시각을 옮기면
        /// 키가 바뀌고, 그 키로 매여 있던 지난 복용 기록이 떨어져 나간다.
        /// 아침·점심·저녁·취침은 시각을 옮겨도 키가 그대로라 여기 오지 않는다.
        var slotKeyRenames: [String: String] = [:]
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

        renameSlotKeys(edit.slotKeyRenames, for: medicationID, in: context)

        save("약 수정", in: context)
    }

    /// 이 날짜보다 나중에 적용된 용량 변경이 이미 있는가.
    private static func hasLaterChange(
        than changedAt: Date,
        for medicationID: UUID,
        in context: ModelContext
    ) -> Bool {
        let descriptor = FetchDescriptor<DoseChangeRecord>(
            predicate: #Predicate { $0.medicationID == medicationID }
        )
        return ((try? context.fetch(descriptor)) ?? []).contains { $0.changedAt > changedAt }
    }

    /// 옮겨진 시간대의 지난 기록도 함께 옮긴다.
    ///
    /// 이것을 하지 않으면 직접 넣은 시간대의 시각을 고치는 순간, 그 시간대에
    /// 이미 "먹었어요" 라고 답해 둔 지난 날들이 전부 미답으로 돌아가
    /// "기록 없이 지나간 시간대" 가 같은 질문을 다시 묻는다(QA 2026-09-19).
    /// 같은 질문을 반복하는 것은 이 앱이 가장 하지 않으려는 일이다.
    ///
    /// 알림 식별자도 같은 키를 쓰므로, 예약된 알림은 바깥에서
    /// `ReminderPlanner.reschedule` 이 통째로 다시 깔아 맞춘다.
    private static func renameSlotKeys(
        _ renames: [String: String],
        for medicationID: UUID,
        in context: ModelContext
    ) {
        guard !renames.isEmpty else { return }

        let descriptor = FetchDescriptor<DoseEventRecord>(
            predicate: #Predicate { $0.medicationID == medicationID }
        )
        for event in (try? context.fetch(descriptor)) ?? [] {
            guard let old = event.slotKey, let new = renames[old] else { continue }
            event.slotKey = new
        }
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

        // **더 나중의 변경이 이미 있으면 지금 값을 앞으로 당기지 않는다.**
        // 9/10 에 20mg 으로 바꿔 둔 뒤 9/3 에 15mg 이었다는 걸 뒤늦게 적으면,
        // 순서를 안 보면 현재 표기가 15mg 으로 되돌아간다 - 재고와 소진
        // 예측까지 옛 개수로 계산된다(QA 2026-09-19). 이력에는 남기되
        // 지금 값은 건드리지 않는다.
        let applies = !hasLaterChange(than: changedAt, for: medicationID, in: context)

        if applies, let toText { record.strengthText = toText }

        if applies, let dose = newDosePerIntake {
            let descriptor = FetchDescriptor<ScheduleRecord>(
                predicate: #Predicate { $0.medicationID == medicationID }
            )
            for schedule in (try? context.fetch(descriptor)) ?? [] {
                schedule.dosePerIntake = DecimalQuantity.snapToQuarter(dose)
            }
        }

        // **개수만 바뀐 변경도 이력을 남긴다**(QA 2026-09-22).
        //
        // 예전에는 표기가 안 바뀌면 여기서 그냥 돌아갔다. 그런데 시간대별
        // 1회 개수는 이미 바뀐 뒤다. 그래서 그 변경이 `DoseChangeRecord` 에
        // 없고, `hasLaterChange` 가 그것만 보므로 **나중에 더 과거의 진료를
        // 뒤늦게 적으면 오늘의 개수가 그때 값으로 되돌아갔다** - 사용자는
        // 지난 날짜를 적었을 뿐인데 알림·오늘 화면·소진 예측이 전부 옛
        // 개수로 돈다.
        //
        // 표기가 그대로인 변경은 화면에 "10mg → 10mg" 으로 보이면 안 되므로
        // `DoseChange.isTextual` 이 아닌 줄로 남긴다.
        guard let toText, toText != fromText else {
            if applies, newDosePerIntake != nil {
                let change = DoseChange(
                    medicationID: medicationID,
                    changedAt: changedAt,
                    fromText: fromText,
                    toText: fromText,
                    note: note
                )
                context.insert(DoseChangeRecord.make(from: change))
            }
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
                // 이 정정은 **받기 전** 개수다. 진료를 지울 때 보충만 걷고
                // 이것을 남기면 기준점이 그대로 서서 재고가 음수로 내려간다.
                prescriptionID: prescription.id,
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

    /// 진료 기록 하나와 **그 진료가 더한 보충**을 지운다.
    ///
    /// 진료일을 잘못 고르거나 개수를 잘못 센 사람이 고칠 길이 아예 없었다
    /// (QA 2026-09-21). 지우고 다시 적는 것이 고치는 길이다.
    ///
    /// 이 처방에 매인 재고 사건을 **전부** 걷는다 - 보충과, 진료일에 세어 둔
    /// "받기 전 남아 있던 개수"(정정) 둘 다.
    ///
    /// 한때 보충만 지우고 정정을 남겼다(QA 2026-09-21). 그 정정이 그날
    /// 실제로 센 수이니 기준점으로 남겨도 된다고 생각했는데, 그것은 **받기
    /// 전** 개수라서 받아 온 28정만 사라지고 기준점은 그대로 섰다 - 9/1 에
    /// 4정 세고 28정 받아 20일 먹은 사람이 그 진료를 지우면 재고가 12 가
    /// 아니라 −16 이 됐다. 둘은 한 사건의 두 쪽이다.
    ///
    /// 이 진료에서 적용한 용량 변경은 건드리지 않는다. 약의 지금 용량을
    /// 되돌리는 일은 약 상세의 용량 변경 카드가 맡는다.
    static func delete(prescriptionID: UUID, in context: ModelContext) {
        delete(FetchDescriptor<StockEventRecord>(
            predicate: #Predicate { $0.prescriptionID == prescriptionID }
        ), in: context)

        delete(FetchDescriptor<PrescriptionRecord>(
            predicate: #Predicate { $0.id == prescriptionID }
        ), in: context)

        save("진료 기록 삭제", in: context)
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
