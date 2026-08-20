import SwiftUI
import SwiftData
import JanjanCore

@main
struct TheJanjanApp: App {

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appLock = AppLockManager()
    @StateObject private var proStore = ProStore()

    private let modelContainer: ModelContainer

    init() {
        modelContainer = JanjanModelContainer.make()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task {
                    // 화면이 올라온 뒤 한 번만. 여기서 알림 권한을 조르지는 않는다 —
                    // 권한은 온보딩에서 "왜 필요한지" 한 문장을 보여 준 뒤에 묻는다.
                    await AppServices.shared.start(container: modelContainer)
                    // 상품·권한 확인. 실패해도 무료 기능은 그대로 돈다(체크리스트 3.6).
                    await proStore.reload()
                }
                .overlay {
                    // "일기만 잠그기" 를 켠 경우에는 앱 전체를 덮지 않고,
                    // RootTabView 의 기록 탭 안에서만 덮는다.
                    if appLock.isEnabled, appLock.isLocked, !appLock.diaryOnly {
                        LockScreenView()
                    }
                }
                .environmentObject(appLock)
                .environmentObject(proStore)
                .onChange(of: scenePhase) { _, phase in
                    appLock.handle(scenePhase: phase)
                }
        }
        .modelContainer(modelContainer)
    }
}

/// 앱이 살아 있는 동안 유지되는 것들의 주인.
///
/// NotificationManager 와 PhoneSessionManager 는 로거를 weak 으로만 들고 있어서,
/// 소유자가 없으면 알림 액션이 조용히 사라진다. 그 소유자가 여기다.
@MainActor
final class AppServices {

    static let shared = AppServices()

    private(set) var doseLogger: SwiftDataDoseLogger?
    private(set) var container: ModelContainer?
    private var hasStarted = false

    private init() {}

    func start(container: ModelContainer) {
        guard !hasStarted else { return }
        hasStarted = true
        self.container = container

        let logger = SwiftDataDoseLogger(container: container)
        doseLogger = logger

        NotificationManager.shared.doseLogger = logger
        NotificationManager.shared.bootstrap()

        PhoneSessionManager.shared.doseLogger = logger
        PhoneSessionManager.shared.snapshotProvider = {
            WatchSnapshotBuilder.snapshot(using: container.mainContext)
        }
        PhoneSessionManager.shared.activate()

        // 알림은 매주 반복이라 한 번 깔면 유지되지만, 앱을 지웠다 깔거나
        // 다른 기기에서 iCloud 로 스케줄이 넘어왔을 때는 비어 있다. 열 때마다 맞춰 둔다.
        Task { await ReminderPlanner.reschedule(using: container.mainContext) }
    }

    /// 기록이 바뀌었으니 워치 화면도 새로 그리라고 밀어 준다.
    /// 워치가 없거나 꺼져 있으면 조용히 아무 일도 일어나지 않는다.
    func pushWatchSnapshot() {
        guard let container else { return }
        PhoneSessionManager.shared.pushSnapshot(
            WatchSnapshotBuilder.snapshot(using: container.mainContext)
        )
    }
}
