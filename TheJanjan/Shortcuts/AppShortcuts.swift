import AppIntents

/// 시리에 등록되는 문구. 설치만 하면 "시리야, 더잔잔 약 먹었어" 가 바로 된다.
///
/// 모든 문구에는 앱 이름이 반드시 들어가야 한다(시스템 규칙이라 뺄 수 없다).
/// 이름 없이 "약 먹었어" 만으로 부르고 싶으면 단축어 앱에서 이 동작에 원하는
/// 문구를 직접 붙일 수 있다.
///
/// 위젯 익스텐션이 아니라 앱 타깃에만 둔다. 문구의 주인은 하나면 된다.
struct JanjanShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogNearestDoseIntent(),
            phrases: [
                "\(.applicationName) 약 먹었어",
                "\(.applicationName)에 약 먹었다고 적어 줘",
                "\(.applicationName) 약 기록"
            ],
            shortTitle: "약 먹었어요",
            systemImageName: "pills"
        )
    }
}
