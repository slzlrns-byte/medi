import Foundation
import SwiftData
import JanjanCore

/// 저장소에서 오늘 계획을 읽어 오는 곳.
///
/// 화면은 `@Query` 로 읽지만 위젯과 App Intent 에는 SwiftUI 가 없다. 그렇다고
/// 계산을 한 벌 더 쓰면 둘이 서로 다른 숫자를 말하게 된다 — 그래서 읽어 오는
/// 방법만 다르고 **계산은 화면과 똑같이 `DayPlan.slots` 한 곳**에서 한다.
///
/// 이 파일은 앱과 위젯 익스텐션 **양쪽에 컴파일**된다.
enum TodayPlanReader {

    /// 그 날의 시간대별 계획. 화면이 부르는 것과 같은 함수를 지난다.
    static func slots(on day: Date, in context: ModelContext) -> [DayPlan.SlotLine] {
        let medications = (try? context.fetch(FetchDescriptor<MedicationRecord>()))?.map(\.core) ?? []
        let schedules = (try? context.fetch(FetchDescriptor<ScheduleRecord>()))?.map(\.core) ?? []
        let doseEvents = (try? context.fetch(FetchDescriptor<DoseEventRecord>()))?.map(\.core) ?? []

        return DayPlan.slots(
            on: day,
            schedules: schedules,
            medications: medications,
            doseEvents: doseEvents
        )
    }

    /// 위젯이 보여 줄 한 줄. 아직 답하지 않은 시간대 중 가장 이른 것.
    ///
    /// 지난 시간대를 건너뛰지 않는다. 아침 약을 아직 안 적었는데 점심을 먼저
    /// 들이밀면, 놓친 것이 조용히 묻힌다.
    static func nextPending(on day: Date, in context: ModelContext) -> DayPlan.SlotLine? {
        slots(on: day, in: context).first { !$0.isCompleted }
    }

    /// 시리가 고를 한 줄. 지금 시각과 가장 가까운 미답 시간대.
    ///
    /// 위젯(가장 이른 미답)과 다른 이유는 `DayPlan.nearestPending` 에 적어 뒀다.
    static func nearestPending(at moment: Date, in context: ModelContext) -> DayPlan.SlotLine? {
        DayPlan.nearestPending(in: slots(on: moment, in: context), at: moment)
    }

    /// 그 시간대에서 **아직 답하지 않은 것만** 복용함으로 적는다.
    ///
    /// 이미 건너뜀으로 적어 둔 것은 건드리지 않는다. 사용자가 일부러 고른 답을
    /// 위젯의 손짓 하나가 조용히 덮으면 안 된다. 오늘 화면의 '먹었어요' 와 같은 규칙이다.
    ///
    /// 적은 개수를 돌려준다. 0 이면 이미 다 답해 둔 시간대라는 뜻이다.
    ///
    /// `DoseRecorder` 가 MainActor 라서 여기도 MainActor 다. 읽기(`slots`)는
    /// 그대로 두었다 — 위젯의 TimelineProvider 는 MainActor 가 아닌 곳에서 읽는다.
    @MainActor
    @discardableResult
    static func recordRestTaken(
        slotKey: String,
        on day: Date,
        source: DoseEvent.Source,
        in context: ModelContext
    ) -> Int {
        guard let line = slots(on: day, in: context).first(where: { $0.slotKey == slotKey }) else {
            return 0
        }

        var recorded = 0
        for entry in line.entries where entry.status == nil || entry.status == .unrecorded {
            DoseRecorder.record(
                medicationID: entry.medicationID,
                slotKey: line.slotKey,
                status: .taken,
                source: source,
                on: day,
                quantity: entry.dose,
                in: context
            )
            recorded += 1
        }

        if recorded > 0 {
            try? context.save()
        }
        return recorded
    }
}
