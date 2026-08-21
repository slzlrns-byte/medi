import SwiftUI
import JanjanCore

/// 탭 4개 + 설정 (설계 03절). "오늘" 이 허브이고 나머지는 관리·되돌아보기 용도다.
struct RootTabView: View {

    @State private var selection: Tab = .today
    @State private var isShowingSettings = false

    enum Tab: Hashable {
        case today
        case medications
        case diary
        case report
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayView(isShowingSettings: $isShowingSettings)
                .tabItem { Label("오늘", systemImage: "sun.horizon") }
                .tag(Tab.today)

            MedicationsView()
                .tabItem { Label("약", systemImage: "pills") }
                .tag(Tab.medications)

            DiaryView()
                .tabItem { Label("기록", systemImage: "book.closed") }
                .tag(Tab.diary)

            ReportView()
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
