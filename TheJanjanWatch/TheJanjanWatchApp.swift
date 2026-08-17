import SwiftUI
import JanjanCore

/// 워치 앱은 폰의 축소판이 아니다 (설계 10절).
/// 알림 응답 · 오늘 약 · 증상 빠른기록 · 기분 원탭 네 가지만 하고 나머지는 폰으로 넘긴다.
/// SwiftData 를 쓰지 않는다 — 데이터의 주인은 폰이고 워치는 스냅샷을 그린다.
@main
struct TheJanjanWatchApp: App {

    @StateObject private var session = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(session)
                .onAppear {
                    session.activate()
                }
        }
    }
}
