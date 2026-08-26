#if DEBUG
import Foundation
import JanjanCore

/// 워치 화면을 찍기 위해 예시 스냅샷을 넣고, 열 화면을 고른다.
///
/// **`#if DEBUG` 안에만 있다.** 출시 빌드에서는 컴파일조차 되지 않는다.
///
/// watchOS 는 XCUITest 를 지원하지 않아서 아이폰처럼 눌러 가며 찍을 수 없다.
/// 그래서 `simctl` 로 앱을 띄우되, **어느 화면으로 열지를 실행 인자로 받는다.**
/// 화면마다 앱을 한 번씩 새로 띄워 찍는 셈이다.
enum WatchDemoSeed {

    /// 열고 싶은 화면.
    enum Screen: String {
        case home
        case mood
        case symptom
    }

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var isRequested: Bool {
        arguments.contains("-JanjanSeedDemoData")
    }

    /// `-JanjanScreen mood` 처럼 받는다. 없으면 홈.
    static var requestedScreen: Screen {
        guard let index = arguments.firstIndex(of: "-JanjanScreen"),
              arguments.indices.contains(index + 1),
              let screen = Screen(rawValue: arguments[index + 1])
        else { return .home }
        return screen
    }

    /// 폰이 없어도 화면이 채워지도록 예시 스냅샷을 넣는다.
    ///
    /// 시뮬레이터에는 짝지어진 아이폰이 없어서 그냥 두면 placeholder 만 보인다.
    /// 빈 화면을 찍어 봐야 아무것도 알 수 없다.
    @MainActor
    static func applyIfRequested(to session: WatchSessionManager) {
        guard isRequested else { return }
        session.applyDemoSnapshot(SampleData.watchSnapshot())
    }
}
#endif
