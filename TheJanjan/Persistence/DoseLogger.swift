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
    func logDose(medicationIDs: [UUID], slotKey: String, action: WatchMessage.DoseAction, at date: Date)
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
        at date: Date
    ) {
        guard action != .snooze else {
            // 30분 뒤 재알림은 기록이 아니라 알림 재예약이다.
            NotificationManager.shared.snooze(slotKey: slotKey, medicationIDs: medicationIDs)
            return
        }

        let status: DoseEvent.Status = (action == .taken) ? .taken : .skipped

        for medicationID in medicationIDs {
            let quantity = scheduledQuantity(for: medicationID, slotKey: slotKey)
            let event = DoseEvent(
                medicationID: medicationID,
                scheduledAt: date,
                actualAt: status == .taken ? date : nil,
                status: status,
                source: .notificationAction,
                quantity: quantity,
                kind: .scheduled,
                slotKey: slotKey
            )
            context.insert(DoseEventRecord.make(from: event))
        }
        save("복용 기록")
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
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)

        // 하루 1개 원칙: 같은 날 기록이 있으면 덮어쓴다.
        let descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { $0.date == day }
        )
        if let existing = try? context.fetch(descriptor), let record = existing.first {
            record.moodScore = CheckIn.Mood(score).score
            record.updatedAt = date
        } else {
            let checkIn = CheckIn(date: day, mood: CheckIn.Mood(score), updatedAt: date)
            context.insert(CheckInRecord.make(from: checkIn))
        }
        save("기분 기록")
    }

    /// 그 시간대에 예정된 1회 개수. 스케줄을 못 찾으면 1정으로 둔다.
    private func scheduledQuantity(for medicationID: UUID, slotKey: String) -> Decimal {
        let descriptor = FetchDescriptor<ScheduleRecord>(
            predicate: #Predicate { $0.medicationID == medicationID && $0.slotKey == slotKey }
        )
        guard let matches = try? context.fetch(descriptor), let first = matches.first else { return 1 }
        return first.dosePerIntake
    }

    private func save(_ what: String) {
        do {
            try context.save()
        } catch {
            logger.error("\(what, privacy: .public) 저장 실패: \(error.localizedDescription, privacy: .public)")
        }
    }
}
