import SwiftUI
import GoogleMobileAds
import JanjanCore

// 광고를 아는 유일한 파일이다(2026-09-19 도입 결정).
//
// 한 곳에 모아 둔 이유: 광고는 "조금 넣고 시작해서 더 붙일지 뺄지 나중에
// 정한다" 는 전제로 들어왔다. 빼기로 하면 이 파일과 project.yml 의 의존성
// 한 줄, 그리고 부르는 자리 둘(RootTabView 의 bannerSlot · ReportView 의
// 내보내기)만 걷어 내면 된다.
//
// 지키는 규칙:
//   · **비개인화 광고만 쓴다.** 애플이 건강·의료 데이터 기반 타겟 광고를
//     금지하므로(5.1.3) 선택이 아니라 조건이다. 덕분에 추적 동의(ATT)
//     팝업이 필요 없고 "추적하지 않습니다" 를 계속 지킨다.
//   · **Pro 에게는 아무것도 부르지 않는다.** 화면이 먼저 isPro 를 보고
//     여기까지 오지 않는다 - SDK 를 깨우는 일조차 없다.
//   · **마음을 적는 자리에는 두지 않는다.** 배너를 다는 곳을 RootTabView 가
//     탭별로 정하고, 기록 탭에는 달지 않는다(QA 2026-09-19 - 처음에는
//     TabView 통째로 달아 기록 탭에도 붙었다).
enum JanjanAds {

    // MARK: - 광고 단위

    /// AdMob 광고 단위. 앱 ID 는 Info.plist 의 GADApplicationIdentifier 에
    /// 있고 같은 계정이어야 한다(앞자리 8133411184190419).
    ///
    /// 비밀이 아니다 - 앱 바이너리에 그대로 실려 누구나 볼 수 있는 값이라
    /// 저장소에 두어도 된다.
    enum Unit {
        /// 실제 단위 (2026-09-19 발급).
        static let banner = "ca-app-pub-8133411184190419/8295274985"

        /// 실제 단위 (2026-09-19 발급).
        static let rewarded = "ca-app-pub-8133411184190419/7421177012"
    }

    // MARK: - 시작

    private static var didStart = false

    /// 무료 사용자가 광고를 처음 만나기 직전에만 깨운다.
    /// Pro 로 시작한 사람의 기기에서는 SDK 가 영영 켜지지 않는다.
    @MainActor
    static func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        GADMobileAds.sharedInstance().start(completionHandler: nil)
    }

    /// 모든 요청이 지나는 한 곳. 비개인화(npa=1)를 여기서 한 번만 건다.
    /// 배너와 보상형이 둘 다 이 함수를 거치므로 처리방침의 "비개인화 광고만
    /// 요청한다" 는 문장이 코드로 지켜진다.
    static func request() -> GADRequest {
        let request = GADRequest()
        let extras = GADExtras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        return request
    }

    /// SDK 가 광고를 띄울 때 필요한 화면. 없으면 광고를 포기한다(크래시하지 않는다).
    @MainActor
    static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?
            .rootViewController
    }
}

// MARK: - 하단 띠 배너

/// 배너가 실제로 붙었는지. 안 붙었으면 자리를 0 으로 접어 빈 띠를 남기지 않는다.
@MainActor
final class BannerState: ObservableObject {
    @Published var isLoaded = false
}

/// 탭 화면 아래에 붙는 띠. 무료에게만 보인다.
struct JanjanBannerView: UIViewRepresentable {

    static let height: CGFloat = 50

    @ObservedObject var state: BannerState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeUIView(context: Context) -> GADBannerView {
        JanjanAds.startIfNeeded()
        let view = GADBannerView(adSize: GADAdSizeBanner)
        view.adUnitID = JanjanAds.Unit.banner
        view.rootViewController = JanjanAds.rootViewController
        view.delegate = context.coordinator
        view.load(JanjanAds.request())
        return view
    }

    func updateUIView(_ view: GADBannerView, context: Context) {
        // 앱이 뒤로 갔다 오면 rootViewController 가 바뀌어 있을 수 있다.
        if view.rootViewController == nil {
            view.rootViewController = JanjanAds.rootViewController
        }
    }

    /// 로드 성공·실패를 상태로 옮긴다. 네트워크가 없거나 채울 광고가 없는
    /// 일은 드물지 않고, 그때 회색 띠만 남으면 고장처럼 보인다(QA 2026-09-19).
    final class Coordinator: NSObject, GADBannerViewDelegate {

        private let state: BannerState

        init(state: BannerState) { self.state = state }

        func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
            Task { @MainActor in state.isLoaded = true }
        }

        func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
            Task { @MainActor in state.isLoaded = false }
        }
    }
}

/// 배너를 붙이는 손잡이. Pro 면 아무것도 하지 않는다.
///
/// **이것을 TabView 통째에 걸지 않는다.** 탭마다 따로 단다 - 기록 탭은
/// 기분과 증상을 적는 자리라 광고를 두지 않기로 했다.
struct BannerSlot: ViewModifier {

    @EnvironmentObject private var pro: ProStore
    @StateObject private var state = BannerState()

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !pro.isPro {
                    JanjanBannerView(state: state)
                        // 광고가 안 붙었으면 자리를 접는다.
                        .frame(height: state.isLoaded ? JanjanBannerView.height : 0)
                        .frame(maxWidth: .infinity)
                        .background(state.isLoaded ? Color.janjan(.surface2) : Color.clear)
                        .clipped()
                }
            }
            // 구독이 끝나 배너가 돌아올 때 레이아웃이 툭 튀지 않게 한다.
            .animation(.easeInOut(duration: 0.2), value: pro.isPro)
            .animation(.easeInOut(duration: 0.2), value: state.isLoaded)
    }
}

extension View {
    /// 무료 사용자에게 하단 띠 배너를 붙인다. 기록 탭에는 쓰지 않는다.
    func bannerSlot() -> some View { modifier(BannerSlot()) }
}

// MARK: - 보상형 광고 (내보내기)

/// "광고를 보고 받기". 강제로 끼어드는 전면 광고가 아니라 사용자가 눌러서
/// 여는 교환이다 - 진료 준비를 하는 손을 막지 않는다.
@MainActor
final class RewardedAdLoader: NSObject, ObservableObject {

    private var ad: GADRewardedAd?
    private var isLoading = false

    /// 이번에 띄운 광고에서 보상을 받았는지. 도중에 닫으면 false 로 남는다.
    private var didEarnThisShow = false
    private var onReward: (() -> Void)?
    private var onSkip: (() -> Void)?

    /// 미리 받아 둔다. 누른 뒤에 받으면 몇 초를 기다리게 된다.
    func preload() {
        guard ad == nil, !isLoading else { return }
        JanjanAds.startIfNeeded()
        isLoading = true
        GADRewardedAd.load(withAdUnitID: JanjanAds.Unit.rewarded, request: JanjanAds.request()) { [weak self] ad, _ in
            Task { @MainActor in
                self?.ad = ad
                self?.isLoading = false
            }
        }
    }

    /// 광고를 보여 주고, 끝까지 봤으면 `onReward` 를, 도중에 닫았으면
    /// `onSkip` 을 부른다.
    ///
    /// **광고를 못 받았으면 그냥 통과시킨다.** 네트워크가 없다고 해서 진료에
    /// 들고 갈 종이를 못 만들게 하지는 않는다 - 광고는 부탁이지 통행료가 아니다.
    func show(onReward: @escaping () -> Void, onSkip: @escaping () -> Void) {
        guard let ad, let root = JanjanAds.rootViewController else {
            onReward()
            preload()
            return
        }
        self.ad = nil
        self.onReward = onReward
        self.onSkip = onSkip
        didEarnThisShow = false
        ad.fullScreenContentDelegate = self
        ad.present(fromRootViewController: root) { [weak self] in
            guard let self else { return }
            self.didEarnThisShow = true
            self.onReward?()
            self.onReward = nil
        }
    }

    private func finish() {
        if !didEarnThisShow { onSkip?() }
        onReward = nil
        onSkip = nil
        preload()
    }
}

extension RewardedAdLoader: GADFullScreenContentDelegate {

    nonisolated func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        Task { @MainActor in self.finish() }
    }

    /// 띄우는 데 실패하면 광고 없이 통과시킨다. 여기서 막으면 잃는 것이
    /// 광고 한 번이 아니라 진료 준비다.
    nonisolated func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in
            self.didEarnThisShow = true
            self.onReward?()
            self.finish()
        }
    }
}
