import SwiftUI
import JanjanCore

/// 탭 4개 + 설정 (설계 03절). "오늘" 이 허브이고 나머지는 관리·되돌아보기 용도다.
struct RootTabView: View {

    @State private var selection: Tab = .today
    @State private var isShowingSettings = false
    /// 서체·테마 선택. 값이 바뀌면 각 탭의 내용을 id 로 갈아 끼워 새 값으로 다시 그린다.
    /// TabView 자체에 id 를 걸면 열려 있는 설정 시트까지 닫혀 버려서 내용에만 건다.
    @AppStorage(JanjanFontChoice.defaultsKey) private var fontChoiceRaw = JanjanFontChoice.standard.rawValue
    @AppStorage(JanjanTheme.defaultsKey) private var themeRaw = JanjanTheme.standard.rawValue

    private var redrawKey: String { "\(fontChoiceRaw)-\(themeRaw)" }

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
                .tabItem { Label("오늘", systemImage: "sun.horizon") }
                .tag(Tab.today)

            MedicationsView()
                .id(redrawKey)
                .tabItem { Label("약", systemImage: "pills") }
                .tag(Tab.medications)

            DiaryView()
                .id(redrawKey)
                .tabItem { Label("기록", systemImage: "book.closed") }
                .tag(Tab.diary)

            ReportView()
                .id(redrawKey)
                .tabItem { Label("리포트", systemImage: "chart.bar") }
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
