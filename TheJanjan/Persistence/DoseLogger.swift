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

        let status: DoseEvent.Status = (action == .taken) ? .taken : .skipped

        // 저장 규칙은 DoseRecorder 한 곳에만 있다. 같은 시간대의 기록은 덮어쓴다 —
        // 알림에서 복용함을 누른 뒤 앱에서 건너뜀으로 고쳐도 재고가 두 번 깎이지 않는다.
        for medicationID in medicationIDs {
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
