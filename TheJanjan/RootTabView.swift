import SwiftUI
import JanjanCore

/// 탭 4개 + 설정 (설계 03절). "오늘" 이 허브이고 나머지는 관리·되돌아보기 용도다.
struct RootTabView: View {

    @EnvironmentObject private var lock: AppLockManager

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

            // "일기만 잠그기" 를 켰으면 이 탭만 잠긴다. 나머지 탭은 그대로 열린다.
            Group {
                if lock.isEnabled, lock.diaryOnly, lock.isLocked {
                    LockScreenView()
                } else {
                    DiaryView()
                }
            }
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
}
