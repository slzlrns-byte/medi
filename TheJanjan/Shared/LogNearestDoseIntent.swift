import AppIntents
import Foundation
import SwiftData
import WidgetKit
import JanjanCore

/// "시리야, 더잔잔 약 먹었어" — 화면 없이 목소리로만 적는 길.
///
/// 무엇을 적을지 보여 줄 화면이 없으므로 지금 시각과 가장 가까운 미답 시간대를
/// 고른다(규칙은 `DayPlan.nearestPending`). 무엇을 적었는지는 대화문이 되돌려
/// 말해 주고, 어긋나게 적혔으면 앱의 오늘 화면에서 그 시간대를 열어 고치면 된다.
///
/// **대화문에 약 이름은 넣지 않는다.** 시리는 소리 내어 읽는다. 옆에 사람이
/// 있을 때 약 이름이 낭독되면 안 된다 — "잠금화면에서 약 이름 숨기기" 와 같은
/// 철학이다. 시간대와 개수까지만 말한다.
struct LogNearestDoseIntent: AppIntent {

    static var title: LocalizedStringResource = "약 먹었다고 기록하기"
    static var description = IntentDescription("지금 시각과 가장 가까운, 아직 답하지 않은 시간대를 복용함으로 적어요.")

    /// 앱을 띄우지 않는다. 말로 끝나야 말로 하는 의미가 있다.
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = JanjanModelContainer.make()
        let context = ModelContext(container)
        let now = Date()

        let medicationCount = (try? context.fetchCount(FetchDescriptor<MedicationRecord>())) ?? 0
        guard medicationCount > 0 else {
            return .result(dialog: "아직 등록된 약이 없어요. 앱에서 먼저 약을 추가해 주세요.")
        }

        guard let line = TodayPlanReader.nearestPending(at: now, in: context) else {
            return .result(dialog: "오늘 약은 이미 다 챙기셨어요.")
        }

        let recorded = TodayPlanReader.recordRestTaken(
            slotKey: line.slotKey,
            on: now,
            source: .siri,
            in: context
        )

        // 적었으면 위젯도 같은 사실을 보여야 한다.
        WidgetCenter.shared.reloadAllTimelines()

        guard recorded > 0 else {
            return .result(dialog: "\(line.slot.labelKo)에는 적을 약이 남아 있지 않았어요.")
        }
        return .result(dialog: "\(line.slot.labelKo) 약 \(recorded)개를 복용함으로 적었어요.")
    }
}
