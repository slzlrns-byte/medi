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
                .tabItem { Label(t("리포트", "Report"), systemImage: "chart.bar") }
                .tag(Tab.report)
        }
        .tint(Color.ink)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(AppLockManager())
        .environmentObject(ProStore())
}
