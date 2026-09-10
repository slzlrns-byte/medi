import SwiftUI
import SwiftData
import JanjanCore

@main
struct TheJanjanApp: App {

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appLock = AppLockManager()
    @StateObject private var proStore = ProStore()
    @AppStorage(JanjanLanguage.defaultsKey) private var languageRaw = JanjanLanguage.standard.rawValue

    private let modelContainer: ModelContainer

    init() {
        modelContainer = JanjanModelContainer.make()

        // 화면을 찍기 위한 예시 기록. 실행 인자가 있을 때만, 그리고 DEBUG 에서만 돈다.
        // 개발 머신에 맥이 없어 시뮬레이터를 눈으로 볼 수 없으므로,
        // CI 의 macOS 러너가 이 데이터를 심은 앱을 띄우고 화면을 찍는다.
        #if DEBUG
        if DemoSeed.isRequested {
            MainActor.assumeIsolated {
                DemoSeed.apply(to: modelContainer.mainContext)
            }
        }
        #endif
    }

    /// 앱 전체를 덮어야 하는 상태인가. 잠금은 사용자가 푸는 것이라 되돌리는 쪽은 비워 둔다.
    private var isFullyLocked: Binding<Bool> {
        Binding(
            get: { appLock.isEnabled && appLock.isLocked },
            set: { _ in }
        )
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task {
                    // 화면이 올라온 뒤 한 번만. 여기서 알림 권한을 조르지는 않는다 —
                    // 권한은 온보딩에서 "왜 필요한지" 한 문장을 보여 준 뒤에 묻는다.
                    //
                    // **구독 판정이 activate() 보다 먼저다.** 워치가 큐에 쌓아 둔
                    // 기록은 세션이 열리자마자 도착하는데, 그때 isPro 가 아직
                    // 기본값(false)이면 유료 사용자의 기록이 조용히 버려진다
                    // (QA 2026-09-10). 상품 확인이 실패해도 무료 기능은 그대로
                    // 돈다(체크리스트 3.6).
                    await proStore.reload()
                    AppServices.shared.updatePro(proStore.isPro)
                    await AppServices.shared.start(container: modelContainer)
                }
                // 시트가 아니라 fullScreenCover 로 덮는다.
                //
                // .overlay 는 화면 **위에 올라온 시트 아래**에 깔린다. 복용 기록 시트나
                // 리포트 공유 시트를 열어 둔 채로 앱을 내렸다 다시 열면, 잠겼는데도
                // 그 시트가 그대로 보이고 잠금 화면은 시트 뒤에 숨는다.
                // fullScreenCover 는 모달 계층의 맨 위로 올라가서 그 경로를 막는다.
                //
                .fullScreenCover(isPresented: isFullyLocked) {
                    LockScreenView()
                        .environmentObject(appLock)
                }
                // 기기 인증으로 되찾아 들어왔으면 새 번호를 정하게 한다.
                // 잊은 번호를 그대로 두면 다음에 앱을 열 때 같은 자리에서 또 막힌다.
                .fullScreenCover(isPresented: $appLock.needsNewPasscode) {
                    PasscodeSetupView(mode: .reset) {}
                        .environmentObject(appLock)
                }
                .environmentObject(appLock)
                .environmentObject(proStore)
                // 화면 글자는 설정에서 고른 언어를 따르는데 DatePicker 같은 시스템 부품은
                // 기기 로케일을 따로 본다. 그대로 두면 한국어 화면인데 "Aug 26, 2026" 처럼
                // 어긋난 표기가 나온다(반대도 마찬가지). 그래서 로케일을 설정의 언어에 맞춘다.
                //
                // 위기 상담 연락처는 이것과 무관하게 기기의 **지역**을 본다
                // (Locale.current.region) — 한국어를 쓰지만 해외에 있는 사람에게
                // 한국 번호를 내밀면 안 되기 때문이다.
                .environment(\.locale, Locale(identifier: (JanjanLanguage(rawValue: languageRaw) ?? .standard).localeIdentifier))
                .onChange(of: proStore.isPro) { _, isPro in
                    AppServices.shared.updatePro(isPro)
                }
                .onChange(of: scenePhase) { _, phase in
                    appLock.handle(scenePhase: phase)

                    // 구독이 밤사이 끝나도 Transaction.updates 는 새 거래가 없으면
                    // 울리지 않는다. 앱을 다시 켤 때 권한을 한 번 더 확인하지 않으면
                    // 만료된 채로 Pro 화면이 열려 있게 된다.
                    if phase == .active {
                        Task { _ = await proStore.refreshEntitlements() }
                    }
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

    /// 워치 앱 전체가 Pro 기능이라, 워치로 무엇을 보낼지 정하려면 구독 상태를 알아야 한다.
    /// 워치에는 StoreKit 을 올리지 않는다 — 판단은 폰에서 하고 결과만 건너간다.
    private(set) var isPro = false

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
        PhoneSessionManager.shared.snapshotProvider = { [weak self] in
            WatchSnapshotBuilder.snapshot(
                using: container.mainContext,
                isPro: self?.isPro ?? false
            )
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
            WatchSnapshotBuilder.snapshot(using: container.mainContext, isPro: isPro)
        )
    }

    /// 구독 상태가 바뀌었다. 워치가 들고 있는 그림도 따라가야 한다 —
    /// 구독이 끝났는데 워치에 오늘 일정이 그대로 남아 있으면 안 되고,
    /// 방금 구독했는데 잠긴 화면이 남아 있어도 안 된다.
    func updatePro(_ isPro: Bool) {
        guard self.isPro != isPro else { return }
        self.isPro = isPro
        pushWatchSnapshot()
    }
}
