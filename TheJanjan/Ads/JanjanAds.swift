import SwiftUI
import GoogleMobileAds
import JanjanCore

// 광고를 아는 유일한 파일이다(2026-09-19 도입 결정).
//
// 한 곳에 모아 둔 이유: 광고는 "조금 넣고 시작해서 더 붙일지 뺄지 나중에
// 정한다" 는 전제로 들어왔다. 빼기로 하면 이 파일과 project.yml 의 의존성
// 한 줄을 지우고, 부르는 자리 셋(RootTabView 배너 · ReportView 내보내기 ·
// 설정 안내)만 걷어 내면 된다.
//
// 지키는 규칙:
//   · **비개인화 광고만 쓴다.** 애플이 건강·의료 데이터 기반 타겟 광고를
//     금지하므로(5.1.3) 선택이 아니라 조건이다. 덕분에 추적 동의(ATT)
//     팝업이 필요 없고 "추적하지 않습니다" 를 계속 지킨다.
//   · **Pro 에게는 아무것도 부르지 않는다.** 화면이 먼저 isPro 를 보고
//     여기까지 오지 않는다 - SDK 를 깨우는 일조차 없다.
//   · **마음을 적는 자리에는 두지 않는다.** 배너는 탭 화면 아래에만 붙고,
//     기록·증상 시트는 화면을 덮으므로 구조적으로 가려진다.
enum JanjanAds {

    // MARK: - 광고 단위

    /// 지금은 구글이 공개한 **테스트 단위**다. AdMob 계정을 만들면 이 셋과
    /// Info.plist 의 GADApplicationIdentifier 를 함께 바꾼다.
    /// 실제 값이 아니면 광고가 안 나올 뿐 앱은 멀쩡히 돈다.
    enum Unit {
        static let banner = "ca-app-pub-3940256099942544/2934735716"
        static let rewarded = "ca-app-pub-3940256099942544/1712485313"
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

/// 탭 화면 아래에 붙는 띠. 무료에게만 보인다.
///
/// 자리를 미리 잡아 두지 않는다 - 광고가 안 붙으면 높이 0으로 사라져서
/// 빈 회색 띠가 남지 않는다.
struct JanjanBannerView: UIViewRepresentable {

    static let height: CGFloat = 50

    func makeUIView(context: Context) -> GADBannerView {
        JanjanAds.startIfNeeded()
        let view = GADBannerView(adSize: GADAdSizeBanner)
        view.adUnitID = JanjanAds.Unit.banner
        view.rootViewController = JanjanAds.rootViewController
        view.load(JanjanAds.request())
        return view
    }

    func updateUIView(_ view: GADBannerView, context: Context) {
        // 앱이 뒤로 갔다 오면 rootViewController 가 바뀌어 있을 수 있다.
        if view.rootViewController == nil {
            view.rootViewController = JanjanAds.rootViewController
        }
    }
}

/// 배너를 붙이는 손잡이. Pro 면 아무것도 하지 않는다.
struct BannerSlot: ViewModifier {

    @EnvironmentObject private var pro: ProStore

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !pro.isPro {
                    JanjanBannerView()
                        .frame(height: JanjanBannerView.height)
                        .frame(maxWidth: .infinity)
                        .background(Color.janjan(.surface2))
                }
            }
    }
}

extension View {
    /// 무료 사용자에게 하단 띠 배너를 붙인다.
    func bannerSlot() -> some View { modifier(BannerSlot()) }
}

// MARK: - 보상형 광고 (내보내기)

/// "광고를 보고 받기". 강제로 끼어드는 전면 광고가 아니라 사용자가 눌러서
/// 여는 교환이다 - 진료 준비를 하는 손을 막지 않는다.
@MainActor
final class RewardedAdLoader: ObservableObject {

    @Published private(set) var isBusy = false

    private var ad: GADRewardedAd?

    /// 미리 받아 둔다. 누른 뒤에 받으면 몇 초를 기다리게 된다.
    func preload() {
        guard ad == nil, !isBusy else { return }
        JanjanAds.startIfNeeded()
        isBusy = true
        GADRewardedAd.load(withAdUnitID: JanjanAds.Unit.rewarded, request: JanjanAds.request()) { [weak self] ad, _ in
            Task { @MainActor in
                self?.ad = ad
                self?.isBusy = false
            }
        }
    }

    /// 광고를 보여 주고 끝나면 `onReward` 를 부른다.
    ///
    /// **광고를 못 받았으면 그냥 통과시킨다.** 네트워크가 없다고 해서 진료에
    /// 들고 갈 종이를 못 만들게 하지는 않는다 - 광고는 부탁이지 통행료가 아니다.
    func show(onReward: @escaping () -> Void) {
        guard let ad, let root = JanjanAds.rootViewController else {
            onReward()
            preload()
            return
        }
        self.ad = nil
        ad.present(fromRootViewController: root) {
            onReward()
        }
        preload()
    }
}
