import Combine
import Foundation
import StoreKit
import JanjanCore

/// 시뮬레이터·UI 확인용 강제 Pro. 릴리스 빌드에서는 컴파일 시점에 false 로 굳는다
/// (체크리스트 6.5 — 디버그 백도어가 제출 빌드에 남지 않게).
///
///     xcodebuild ... 또는 스킴 환경변수:  JANJAN_FORCE_PRO=1
private let janjanForcesPro: Bool = {
    #if DEBUG
    return ProcessInfo.processInfo.environment["JANJAN_FORCE_PRO"] == "1"
    #else
    return false
    #endif
}()

/// StoreKit 2 구독 하나를 다루는 전부. 서버도 영수증 검증 서버도 없고,
/// 애플이 서명한 `currentEntitlements` 만 진실로 삼는다.
///
/// 규칙 두 가지를 코드로 지킨다.
/// 1. **스토어가 없어도 앱은 멀쩡해야 한다** — 상품이 비었을 때 크래시하거나 빈 화면을
///    보이지 않고 `storeUnavailable` 로 알린다(체크리스트 3.6). 무료 기능은 그대로 돈다.
/// 2. **검증된 거래만 센다** — `.unverified` 는 권한으로 세지 않는다.
@MainActor
final class ProStore: ObservableObject {

    /// 페이월에 보여 줄 상품. 연간이 먼저다.
    @Published private(set) var products: [Product] = []

    /// Pro 권한. 화면은 이 값 하나만 본다.
    @Published private(set) var isPro = janjanForcesPro

    /// 연간 7일 무료 체험을 받을 수 있는지. 못 받는 계정에는 체험 문구를 아예 숨긴다(3.1.2(b)).
    @Published private(set) var isYearlyTrialEligible = false

    /// 상품을 못 불러온 상태. 네트워크일 수도, 계약·상품 상태일 수도 있다.
    @Published private(set) var storeUnavailable = false

    @Published private(set) var isLoading = false

    /// 사용자에게 보여 줄 마지막 안내. 사용자가 닫을 수 있어야 하니 var 로 둔다.
    @Published var lastError: String?

    static let storeUnavailableMessageKo =
        "지금은 스토어에 연결할 수 없어요. 무료 기능은 그대로 쓸 수 있어요."

    private var updatesTask: Task<Void, Never>?

    /// `@MainActor` 클래스의 암묵적 init 은 `App` 의 프로퍼티 초깃값에서 부를 수 없다
    /// (AppLockManager 와 같은 이유). 그래서 init 은 비워 두고 `start()` 를 따로 둔다.
    nonisolated init() {}

    // MARK: - 시작

    /// 앱 밖에서 일어난 변화(가족 공유, 환불, 체험 종료, 다른 기기 구매)를 듣기 시작한다.
    /// 여러 번 불러도 리스너는 하나다. `reload()` 가 먼저 이것을 부른다.
    func start() {
        guard updatesTask == nil else { return }

        updatesTask = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
    }

    // MARK: - 상품

    var yearlyProduct: Product? { product(for: ProProduct.yearly) }
    var monthlyProduct: Product? { product(for: ProProduct.monthly) }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    /// 연간 가격을 12로 나눈 "월 ₩1,658 꼴". 통화·자릿수는 상품의 형식을 그대로 따른다.
    var yearlyMonthlyEquivalentText: String? {
        guard let yearly = yearlyProduct else { return nil }
        return (yearly.price / 12).formatted(yearly.priceFormatStyle)
    }

    /// 화면에서 `Task` 를 만들지 않아도 되게 감싼 것.
    func load() {
        Task { await reload() }
    }

    func reload() async {
        start()

        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await Product.products(for: ProProduct.allIDs)
            // 애플은 요청 순서를 보장하지 않는다. 연간을 먼저 보이도록 우리가 정렬한다.
            products = ProProduct.allIDs.compactMap { id in
                fetched.first { $0.id == id }
            }
            storeUnavailable = products.isEmpty
            if products.isEmpty {
                lastError = Self.storeUnavailableMessageKo
            }
        } catch {
            products = []
            storeUnavailable = true
            lastError = Self.storeUnavailableMessageKo
        }

        await refreshEntitlements()
        await yearlyTrialEligible()
    }

    // MARK: - 권한

    /// 검증된 거래만 세고, 환불·만료된 것은 뺀다.
    @discardableResult
    func refreshEntitlements() async -> Bool {
        var entitled = janjanForcesPro

        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expiration = transaction.expirationDate, expiration <= Date() { continue }
            if ProProduct.allIDs.contains(transaction.productID) {
                entitled = true
            }
        }

        isPro = entitled
        return entitled
    }

    /// 연간 상품에 소개 혜택(7일 무료)이 있고, 이 계정이 아직 써 본 적 없을 때만 true.
    @discardableResult
    func yearlyTrialEligible() async -> Bool {
        guard let subscription = yearlyProduct?.subscription,
              subscription.introductoryOffer != nil
        else {
            isYearlyTrialEligible = false
            return false
        }

        let eligible = await subscription.isEligibleForIntroOffer
        isYearlyTrialEligible = eligible
        return eligible
    }

    // MARK: - 구매 · 복원

    func purchase(_ product: Product) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlements()
                case .unverified:
                    // 서명이 맞지 않는 거래는 권한으로 세지 않는다.
                    lastError = "구매를 확인하지 못했어요. 잠시 뒤 다시 시도해 주세요."
                }
            case .userCancelled:
                break
            case .pending:
                // 가족 승인 대기 등. 승인되면 Transaction.updates 로 들어온다.
                lastError = "승인을 기다리는 중이에요. 승인되면 자동으로 열려요."
            @unknown default:
                break
            }
        } catch {
            lastError = "구매를 마치지 못했어요. 잠시 뒤 다시 시도해 주세요."
        }
    }

    /// 복원. 로그인이 없는 앱이라 복원은 애플 계정 동기화 한 번이면 끝난다.
    func restore() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPro {
                lastError = "이 애플 계정에서 복원할 구독을 찾지 못했어요."
            }
        } catch {
            lastError = "복원을 마치지 못했어요. 잠시 뒤 다시 시도해 주세요."
        }
    }
}
