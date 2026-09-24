import Foundation
import OSLog
import SwiftData
import JanjanCore

/// 알림 액션과 워치에서 올라온 기록을 실제로 저장하는 통로.
///
/// 프로토콜로 끊어 두는 이유: 알림 델리게이트는 앱이 떠 있지 않을 때도 불리므로
/// 화면·뷰모델에 의존해서는 안 된다. 테스트에서는 가짜 구현을 끼운다.
@MainActor
protocol DoseLogging: AnyObject {
    func logDose(
        medicationIDs: [UUID],
        slotKey: String,
        action: WatchMessage.DoseAction,
        source: DoseEvent.Source,
        at date: Date
    )
    func logSymptom(symptomID: String, severity: Int, at date: Date, source: SymptomEntry.Source)
    func logMood(score: Int, at date: Date)
}

/// SwiftData 에 바로 쓰는 구현.
///
/// 알림 액션은 앱이 백그라운드에 있을 때 오므로 화면 갱신을 기다리지 않고
/// 곧바로 저장한 뒤 `save()` 까지 마친다.
@MainActor
final class SwiftDataDoseLogger: DoseLogging {

    private let logger = Logger(subsystem: Janjan.appBundleID, category: "dose-logger")
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    private var context: ModelContext { container.mainContext }

    func logDose(
        medicationIDs: [UUID],
        slotKey: String,
        action: WatchMessage.DoseAction,
        source: DoseEvent.Source,
        at date: Date
    ) {
        guard action != .snooze else {
            // 30분 뒤 재알림은 기록이 아니라 알림 재예약이다.
            NotificationManager.shared.snooze(slotKey: slotKey, medicationIDs: medicationIDs)
            return
        }

        guard !medicationIDs.isEmpty else {
            // 워치가 ID 없는 옛 스냅샷 줄을 눌리지 않게 막고 있지만, 여기서도
            // 조용히 지나가지 않는다 - 빈 기록이 성공처럼 보이면 안 된다.
            logger.error("약 ID 없는 복용 기록이 왔습니다. 무시합니다. slotKey=\(slotKey, privacy: .public)")
            return
        }

        let status: DoseEvent.Status = (action == .taken) ? .taken : .skipped

        // 이미 지워진 약의 ID 가 섞여 올 수 있다 - 옛 스냅샷을 쥔 워치, 걷히기 전의
        // 잠금화면 알림. 주인 없는 기록은 복약률에 조용히 섞이므로 여기서 거른다.
        let knownIDs = medicationIDs.filter { medicationID in
            let descriptor = FetchDescriptor<MedicationRecord>(
                predicate: #Predicate { $0.id == medicationID }
            )
            return ((try? context.fetchCount(descriptor)) ?? 0) > 0
        }
        if knownIDs.count != medicationIDs.count {
            logger.error("지워진 약 \(medicationIDs.count - knownIDs.count)개의 복용 기록을 무시했습니다.")
        }
        guard !knownIDs.isEmpty else {
            AppServices.shared.pushWatchSnapshot()
            return
        }

        // **이미 답한 약은 건드리지 않는다**(QA 2026-09-22). 알림·워치의
        // "전부 복용함" 은 시간대 하나에 묶인 약 전부에 걸리는데, 그중 하나를
        // 앱에서 일부러 "건너뜀" 으로 적어 둔 사람이 있다. 그대로 덮으면 그
        // 건너뜀이 복용함이 되고 재고가 한 알 빠진다. 앱 타일의 "먹었어요" 와
        // 같게 **미답만** 채운다. 답을 고치는 일은 앱 화면이 약별로 한다.
        let pending = knownIDs.filter { medicationID in
            !DoseRecorder.isAnswered(medicationID: medicationID, slotKey: slotKey, near: date, in: context)
        }
        guard !pending.isEmpty else {
            AppServices.shared.pushWatchSnapshot()
            return
        }

        // 저장 규칙은 DoseRecorder 한 곳에만 있다.
        for medicationID in pending {
            DoseRecorder.record(
                medicationID: medicationID,
                slotKey: slotKey,
                status: status,
                source: source,
                at: date,
                in: context
            )
        }
        save("복용 기록")
        AppServices.shared.pushWatchSnapshot()
    }

    func logSymptom(symptomID: String, severity: Int, at date: Date, source: SymptomEntry.Source) {
        let entry = SymptomEntry(
            symptomID: symptomID,
            severity: severity,
            startedAt: date,
            source: source
        )
        context.insert(SymptomEntryRecord.make(from: entry))
        save("증상 기록")
    }

    func logMood(score: Int, at date: Date) {
        // 하루 1개 원칙은 CheckInRecorder 한 곳에 있다. 워치에서 올라온 기분과
        // 오늘 화면에서 고른 기분이 같은 줄을 고쳐 쓴다.
        CheckInRecorder.recordMood(score: score, on: date, at: date, in: context)
        save("기분 기록")
    }

    private func save(_ what: String) {
        do {
            try context.save()
        } catch {
            logger.error("\(what, privacy: .public) 저장 실패: \(error.localizedDescription, privacy: .public)")
        }
    }
}
