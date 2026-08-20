import Foundation
import SwiftData
import JanjanCore

/// 저장소를 읽어 워치가 그릴 오늘 요약을 만든다.
///
/// 워치는 스케줄도 재고도 모른다(설계 10절). 폰이 계산해서 완성된 그림만 보낸다.
/// 계산은 `DayPlan.watchSnapshot` 이 하고, 여기서는 읽어다 넘기기만 한다.
@MainActor
enum WatchSnapshotBuilder {

    static func snapshot(
        using context: ModelContext,
        isPro: Bool,
        on day: Date = Date(),
        calendar: Calendar = .current
    ) -> WatchSnapshot {

        let medications = (try? context.fetch(FetchDescriptor<MedicationRecord>()))?.map(\.core) ?? []
        let schedules = (try? context.fetch(FetchDescriptor<ScheduleRecord>()))?.map(\.core) ?? []

        return DayPlan.watchSnapshot(
            on: day,
            schedules: schedules,
            medications: medications,
            doseEvents: doseEvents(around: day, in: context, calendar: calendar),
            calendar: calendar,
            isPro: isPro
        )
    }

    /// 그 날 앞뒤로만 읽는다. 워치 요약은 하루치라 기록 전체를 훑을 이유가 없다.
    private static func doseEvents(
        around day: Date,
        in context: ModelContext,
        calendar: Calendar
    ) -> [DoseEvent] {

        let start = calendar.startOfDay(for: day)
        guard let from = calendar.date(byAdding: .day, value: -1, to: start),
              let to = calendar.date(byAdding: .day, value: 2, to: start)
        else { return [] }

        let descriptor = FetchDescriptor<DoseEventRecord>(
            predicate: #Predicate { $0.scheduledAt >= from && $0.scheduledAt < to }
        )
        return (try? context.fetch(descriptor))?.map(\.core) ?? []
    }
}
