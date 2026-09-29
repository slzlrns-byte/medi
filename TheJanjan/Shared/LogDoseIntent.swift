import AppIntents
import Foundation
import SwiftData
import WidgetKit
import JanjanCore

/// 위젯의 '먹었어요' 를 실제 기록으로 만드는 손잡이.
///
/// **앱을 열지 않는다.** 이 인텐트는 위젯 익스텐션 안에서 돌면서 앱과 같은
/// 저장소(App Group)를 열고 그 자리에서 적는다. 앱이 켜질 때까지 미뤄 두는
/// 방식이었다면, 앱을 안 여는 날의 기록은 늦거나 사라졌을 것이다.
///
/// 앱 타깃에도 같이 컴파일된다. 그래야 단축어·Siri 에서도 부를 수 있다.
struct LogDoseIntent: AppIntent {

    static var title: LocalizedStringResource = "약 먹었다고 기록하기"
    static var description = IntentDescription("그 시간대에 아직 답하지 않은 약을 복용함으로 적어요.")

    /// 앱을 띄우지 않는다. 위젯에서 누른 손이 화면 전환까지 겪을 이유가 없다.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "시간대")
    var slotKey: String

    init() {}

    init(slotKey: String) {
        self.slotKey = slotKey
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let container = JanjanModelContainer.make()
        let context = ModelContext(container)

        TodayPlanReader.recordRestTaken(
            slotKey: slotKey,
            on: Date(),
            source: .widget,
            in: context
        )

        // 적고 나면 위젯이 '완료' 로 바뀌어야 한다. 그러지 않으면 눌렀는데
        // 아무 일도 없는 것처럼 보여서 한 번 더 누르게 된다.
        WidgetCenter.shared.reloadAllTimelines()

        // 워치 스냅샷은 여기서 밀지 않는다. WatchConnectivity 세션의 주인은 앱이다.
        // 그래서 위젯으로 적은 직후 워치는 잠시 그 약을 '남음' 으로 보여 준다.
        // 앱이 다음에 앞으로 나올 때 따라온다.
        //
        // 그 사이에 워치에서 같은 약을 또 눌러도 안전하다. DoseRecorder 가 같은
        // 날·시간대·약의 기록을 덮어쓰므로 재고가 두 번 깎이지 않는다.

        return .result()
    }
}
