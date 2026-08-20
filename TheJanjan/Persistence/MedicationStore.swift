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

    /// 복용 중 ↔ 중단. 기록은 그대로 두고 앞으로의 일정에서만 뺀다.
    static func setStatus(_ status: Medication.Status, for medicationID: UUID, in context: ModelContext) {
        guard let record = medicationRecord(medicationID, in: context) else { return }
        record.statusRaw = status.rawValue
        save("복용 상태 변경", in: context)
    }

    /// 약과 그에 딸린 모든 줄을 지운다. 되돌릴 수 없다.
    static func delete(medicationID: UUID, in context: ModelContext) {
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
        assert(JanjanSchema.allModels.count == 7, "모델을 추가했다면 전체 삭제에도 넣어 주세요.")

        wipe(MedicationRecord.self, in: context)
        wipe(ScheduleRecord.self, in: context)
        wipe(DoseEventRecord.self, in: context)
        wipe(StockEventRecord.self, in: context)
        wipe(CheckInRecord.self, in: context)
        wipe(SymptomEntryRecord.self, in: context)
        wipe(PrescriptionRecord.self, in: context)

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
