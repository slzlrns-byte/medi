import SwiftUI
import JanjanCore

/// 탭 4개 + 설정 (설계 03절). "오늘" 이 허브이고 나머지는 관리·되돌아보기 용도다.
struct RootTabView: View {

    @State private var selection: Tab = RootTabView.launchTab
    @State private var isShowingSettings = false
    @State private var isShowingPaywall = RootTabView.launchesPaywall

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
    /// 화면 찍기 전용: 뜨자마자 구독 화면을 열지. DEBUG 밖에서는 늘 거짓이다.
    private static var launchesPaywall: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-JanjanShowPaywall")
        #else
        return false
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
                .bannerSlot()
                .tabItem { Label(t("오늘", "Today"), systemImage: "sun.horizon") }
                .tag(Tab.today)

            MedicationsView()
                .id(redrawKey)
                .bannerSlot()
                .tabItem { Label(t("약", "Meds"), systemImage: "pills") }
                .tag(Tab.medications)

            // 기록 탭에는 배너를 달지 않는다. 기분과 증상을 적는 자리이고,
            // 그 순간에 광고를 두지 않기로 했다(2026-09-19). 처음에는 TabView
            // 통째에 달아 이 탭에도 붙었고, 처리방침에 적어 둔 약속과
            // 어긋났다(QA 2026-09-19).
            DiaryView()
                .id(redrawKey)
                .tabItem { Label(t("기록", "Journal"), systemImage: "book.closed") }
                .tag(Tab.diary)

            ReportView()
                .id(redrawKey)
                .bannerSlot()
                .tabItem { Label(t("진료 준비", "Visit prep"), systemImage: "chart.bar") }
                .tag(Tab.report)
        }
        .tint(Color.ink)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        // 화면 찍기 전용: `-JanjanShowPaywall` 이면 뜨자마자 구독 화면을 연다.
        // 페이월은 잠긴 기능을 눌러야 열려서, 인앱결제 심사용 스크린샷을
        // 찍을 길이 달리 없었다(2026-09-20). Pro 가 켜져 있으면 이 화면은
        // 스스로 닫히므로, 찍을 때는 JANJAN_FORCE_PRO 를 꺼야 한다.
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
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
