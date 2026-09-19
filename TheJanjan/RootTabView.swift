import SwiftUI
import JanjanCore

/// 탭 4개 + 설정 (설계 03절). "오늘" 이 허브이고 나머지는 관리·되돌아보기 용도다.
struct RootTabView: View {

    @State private var selection: Tab = RootTabView.launchTab
    @State private var isShowingSettings = false

    /// 화면 찍기 전용: `-JanjanTab report` 처럼 받아 그 탭으로 연다.
    /// 시뮬레이터를 simctl 로만 띄우는 영어 캡처가 탭을 누를 수 없어서다.
    /// DEBUG 밖에서는 늘 오늘 탭이다.
    private static var launchTab: Tab {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-JanjanTab"),
              arguments.indices.contains(index + 1) else { return .today }
        switch arguments[index + 1] {
        case "meds": return .medications
        case "journal": return .diary
        case "report": return .report
        default: return .today
        }
        #else
        return .today
        #endif
    }
    /// 서체·테마·언어 선택. 값이 바뀌면 각 탭의 내용을 id 로 갈아 끼워 새 값으로 다시 그린다.
    /// TabView 자체에 id 를 걸면 열려 있는 설정 시트까지 닫혀 버려서 내용에만 건다.
    @AppStorage(JanjanFontChoice.defaultsKey) private var fontChoiceRaw = JanjanFontChoice.standard.rawValue
    @AppStorage(JanjanTheme.defaultsKey) private var themeRaw = JanjanTheme.standard.rawValue
    @AppStorage(JanjanLanguage.defaultsKey) private var languageRaw = JanjanLanguage.standard.rawValue

    private var redrawKey: String { "\(fontChoiceRaw)-\(themeRaw)-\(languageRaw)" }

    enum Tab: Hashable {
        case today
        case medications
        case diary
        case report
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayView(isShowingSettings: $isShowingSettings)
                .id(redrawKey)
                .tabItem { Label(t("오늘", "Today"), systemImage: "sun.horizon") }
                .tag(Tab.today)

            MedicationsView()
                .id(redrawKey)
                .tabItem { Label(t("약", "Meds"), systemImage: "pills") }
                .tag(Tab.medications)

            DiaryView()
                .id(redrawKey)
                .tabItem { Label(t("기록", "Journal"), systemImage: "book.closed") }
                .tag(Tab.diary)

            ReportView()
                .id(redrawKey)
                .tabItem { Label(t("진료 준비", "Visit prep"), systemImage: "chart.bar") }
                .tag(Tab.report)
        }
        .tint(Color.ink)
        // 무료에게만 붙는 하단 띠. 일기·증상처럼 마음을 적는 자리는 시트로
        // 열려 화면을 덮으므로 그 위에서는 구조적으로 보이지 않는다.
        .bannerSlot()
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        // 무료 위젯의 "먹었어요" 는 기록하는 대신 앱을 연다. 앱이 이미
        // 다른 탭에 떠 있었다면 그대로 앞으로 나올 뿐이라, 기록할 자리인
        // 오늘 탭으로 옮겨 준다. 시간대 키는 아직 쓰지 않는다.
        .onOpenURL { url in
            guard url.scheme == Janjan.urlScheme, url.host == "log" else { return }
            selection = .today
            isShowingSettings = false
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(AppLockManager())
        .environmentObject(ProStore())
}
