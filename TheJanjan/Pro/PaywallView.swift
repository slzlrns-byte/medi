import SwiftUI
import StoreKit
import JanjanCore

/// Pro 페이월. 승인된 시안(scratchpad/paywall.html) 그대로다.
///
/// 심사 3.1.2(a) 가 요구하는 것을 한 화면에 다 둔다: 상품 이름 · 기간 · 가격 ·
/// 자동 갱신 · 체험 후 요금 · 이용약관 · 개인정보처리방침 · 구매 복원 · 구독 관리.
/// 가격 문장은 전부 `product.displayPrice` 에서 만든다 — 코드에 금액을 적어 두면
/// 통화·지역이 다를 때 거짓말이 된다.
struct PaywallView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pro: ProStore

    @State private var selectedPlan: Plan = .yearly

    enum Plan: Hashable {
        case yearly
        case monthly
        case lifetime
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    topBar

                    Spacer(minLength: CGFloat(JanjanSpacing.xl))

                    headline

                    featureCard
                        .padding(.top, CGFloat(JanjanSpacing.xl))

                    Spacer(minLength: CGFloat(JanjanSpacing.xxl))

                    bottomGroup
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.xxl))
                .padding(.top, CGFloat(JanjanSpacing.s))
                .padding(.bottom, CGFloat(JanjanSpacing.xl))
                // 짧은 기기에서는 스크롤되고, 큰 기기에서는 위아래 여백이 벌어진다.
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
        }
        .fogBackground()
        .task { await pro.reload() }
        .onChange(of: pro.isPro) { _, isPro in
            // 구매·복원이 끝나면 조용히 닫는다. 축하 화면은 두지 않는다.
            if isPro { dismiss() }
        }
        // 고른 것이 화면에 없으면 아무것도 안 골라진 페이월이 되고, 큰 버튼을
        // 눌러도 buy() 가 조용히 빠져나간다. 갱신 고지에서는 금액까지 사라진다
        // (3.1.2). 상품 목록이 올 때마다 실제로 그려진 첫 줄로 맞춘다.
        .onChange(of: pro.products) { _, _ in alignSelection() }
        .onAppear { alignSelection() }
    }

    // MARK: - 위쪽

    private var topBar: some View {
        ZStack {
            Text(Janjan.appName(JanjanLanguage.current))
                .janjanBody(12, weight: .medium)
                .tracking(1.6)
                .foregroundStyle(Color.muted)
                .frame(maxWidth: .infinity)

            HStack {
                Button {
                    dismiss()
                } label: {
                    CircleGlyph(
                        systemImage: "xmark",
                        background: .surface,
                        foreground: .ink,
                        diameter: 36
                    )
                    // 동그라미는 36 이지만 손가락 자리는 44 다(QA 2026-09-19).
                    // 하필 무료 사용자가 이 화면에서 제일 먼저 찾는 버튼이다.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(t("닫기", "Close")))

                Spacer()
            }
        }
        .frame(height: 36)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
            Text(t("더 잔잔한 하루를 위해,\nPro", "For a calmer day,\nPro"))
                .janjanDisplay(30, relativeTo: .largeTitle)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)

            // 제목과 기능 목록 사이를 잇는 한 문장. 열 줄이 무엇을 위한
            // 것인지 먼저 말하지 않으면 목록은 읽히지 않는다(2026-09-19).
            Text(t(
                "약을 놓치지 않게 지켜 주고, 진료실에 들고 갈 것을 대신 모아 둬요.",
                "It keeps you from missing a dose, and gathers what you'll bring to your visit."
            ))
                .janjanBody(14)
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 라벤더 타일 안에 출시 시점 Pro. 무엇을 위한 것인지로 묶어 그린다 -
    /// 문구도 묶음도 JanjanCore 가 들고 있다.
    private var featureCard: some View {
        JanjanTile(tint: .lav, padding: CGFloat(JanjanSpacing.xl)) {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.l)) {
                ForEach(ProFeature.launchGroups, id: \.group) { section in
                    VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                        Text(section.group.title(JanjanLanguage.current))
                            .janjanBody(12, weight: .semibold)
                            .foregroundStyle(Color.janjan(.lavInk))
                        ForEach(section.features, id: \.self) { feature in
                            HStack(spacing: CGFloat(JanjanSpacing.s)) {
                                CircleGlyph(
                                    systemImage: "checkmark",
                                    background: .surface,
                                    foreground: .lavInk,
                                    diameter: 22
                                )
                                Text(feature.title(JanjanLanguage.current))
                                    .janjanBody(16, weight: .medium)
                                    .foregroundStyle(Color.ink)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, CGFloat(JanjanSpacing.s))
        }
    }

    // MARK: - 아래쪽

    private var bottomGroup: some View {
        VStack(spacing: 0) {
            if pro.isPro {
                alreadyProCard
            } else if pro.storeUnavailable {
                storeUnavailableCard
            } else if pro.products.isEmpty {
                loadingCard
            } else {
                planCards
                cta
                    .padding(.top, CGFloat(JanjanSpacing.m) + 2)
                disclosure
                    .padding(.top, CGFloat(JanjanSpacing.s))
            }

            if let message = pro.lastError, !pro.storeUnavailable {
                errorLine(message)
                    .padding(.top, CGFloat(JanjanSpacing.s))
            }

            links
                .padding(.top, CGFloat(JanjanSpacing.m) + 2)

            Text(t("무료 기능은 구독 없이 계속 쓸 수 있어요.", "Free features keep working without a subscription."))
                .janjanBody(11)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
                .padding(.top, CGFloat(JanjanSpacing.m))
        }
        .frame(maxWidth: .infinity)
    }

    private var planCards: some View {
        VStack(spacing: CGFloat(JanjanSpacing.xs)) {
            if let yearly = pro.yearlyProduct {
                planCard(
                    plan: .yearly,
                    name: t("연간", "Yearly"),
                    meaning: t("구독 · 해마다 갱신", "Subscription · renews yearly"),
                    price: t("\(yearly.displayPrice) / 년", "\(yearly.displayPrice) / yr"),
                    note: pro.yearlyMonthlyEquivalentText.map { t("월 \($0) 꼴", "≈ \($0) / mo") },
                    tag: pro.isYearlyTrialEligible ? t("7일 무료", "7 days free") : nil
                )
            }
            if let monthly = pro.monthlyProduct {
                planCard(
                    plan: .monthly,
                    name: t("월간", "Monthly"),
                    meaning: t("구독 · 달마다 갱신", "Subscription · renews monthly"),
                    price: t("\(monthly.displayPrice) / 월", "\(monthly.displayPrice) / mo"),
                    note: nil,
                    tag: nil
                )
            }
            // 평생 이용권(2026-09-19 결정). 구독이 아니라는 것이 이 줄의 핵심
            // 정보다 - "한 번 결제" 를 크게 파는 화면은 만들지 않되, 구독 둘과
            // 헷갈리지는 않게 한다.
            if let lifetime = pro.lifetimeProduct {
                planCard(
                    plan: .lifetime,
                    name: t("평생", "Lifetime"),
                    meaning: t("한 번 결제 · 구독 아님", "One-time · not a subscription"),
                    price: lifetime.displayPrice,
                    note: t("갱신 없음", "No renewal"),
                    tag: nil
                )
            }
        }
    }

    /// 상품 한 줄.
    ///
    /// 예전에는 "연간 · ₩19,900 / 년" 처럼 이름과 가격을 한 문장에 붙여 두었다.
    /// 세 줄이 전부 같은 모양의 긴 문장이 되어 무엇이 다른지 한눈에 안 들어왔다
    /// (사용자 지적 2026-09-21). 이름은 왼쪽, 가격은 오른쪽으로 갈라 세로로
    /// 훑을 수 있게 한다 - 이름 셋을 먼저 비교하고, 그다음 가격 셋을 비교한다.
    ///
    /// 가운데 한 줄은 **그것이 무엇인지**를 말한다. 구독인지 아닌지는 이 화면에서
    /// 가장 중요한 차이인데, 예전에는 평생 줄에만 작게 적혀 있었다.
    private func planCard(
        plan: Plan,
        name: String,
        meaning: String,
        price: String,
        note: String?,
        tag: String?
    ) -> some View {
        let isSelected = selectedPlan == plan

        return Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: CGFloat(JanjanSpacing.s)) {
                radio(isSelected: isSelected)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                        Text(name)
                            .janjanDisplay(19)
                            .foregroundStyle(Color.ink)
                        if let tag {
                            Text(tag)
                                .janjanBody(11, weight: .semibold)
                                .foregroundStyle(Color.janjan(.lavInk))
                                .padding(.horizontal, CGFloat(JanjanSpacing.xs))
                                .padding(.vertical, 2)
                                .background(Capsule(style: .continuous).fill(Color.janjan(.lav)))
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    Text(meaning)
                        .janjanBody(12)
                        .foregroundStyle(Color.muted)
                }

                Spacer(minLength: CGFloat(JanjanSpacing.xs))

                VStack(alignment: .trailing, spacing: 2) {
                    Text(price)
                        .janjanBody(16, weight: .semibold)
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                    if let note {
                        Text(note)
                            .janjanBody(11)
                            .foregroundStyle(Color.muted)
                            .monospacedDigit()
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, CGFloat(JanjanSpacing.m))
            .padding(.vertical, CGFloat(JanjanSpacing.s) + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.row), style: .continuous)
                    // 고른 줄은 테두리만이 아니라 바탕도 조금 달라진다. 테두리
                    // 굵기 0.5 차이는 밝은 곳에서 잘 안 보인다.
                    .fill(isSelected ? Color.janjan(.surface2) : Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.row), style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.ink : Color.hairline,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(name), \(meaning), \(price)"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    /// 라디오. 색만으로 선택을 말하지 않으려고 테두리 두께도 함께 바뀐다.
    private func radio(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.ink : Color.surface)
            Circle()
                .strokeBorder(
                    isSelected ? Color.ink : Color.janjan(.line2),
                    lineWidth: 1.5
                )
            if isSelected {
                Circle()
                    .fill(Color.janjan(.surface))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 18, height: 18)
    }

    private var cta: some View {
        BlackPillButton(
            title: ctaTitle,
            isBusy: pro.isLoading,
            // 고른 상품을 실제로 살 수 없으면 눌러도 아무 일이 없다.
            // 죽은 버튼을 살아 있는 것처럼 보이게 두지 않는다.
            isEnabled: selectedProduct != nil,
            action: buy
        )
    }

    /// 지금 고른 줄에 해당하는 상품. 없으면 그 줄은 화면에 그려지지도 않는다.
    private var selectedProduct: Product? {
        switch selectedPlan {
        case .yearly: return pro.yearlyProduct
        case .monthly: return pro.monthlyProduct
        case .lifetime: return pro.lifetimeProduct
        }
    }

    /// 고른 줄이 화면에 없으면 있는 줄로 옮긴다. 상품이 하나도 없을 때는
    /// `loadingCard` 가 대신 서므로 건드리지 않는다.
    private func alignSelection() {
        guard selectedProduct == nil else { return }
        if pro.yearlyProduct != nil { selectedPlan = .yearly }
        else if pro.monthlyProduct != nil { selectedPlan = .monthly }
        else if pro.lifetimeProduct != nil { selectedPlan = .lifetime }
    }

    /// 체험을 받을 수 있을 때만 "무료" 라고 쓴다. 못 받는 계정에 무료라고 쓰면 3.1.2 위반이다.
    private var ctaTitle: String {
        if selectedPlan == .yearly, pro.isYearlyTrialEligible {
            return t("7일 무료로 시작하기", "Start 7 days free")
        }
        return t("Pro 시작하기", "Start Pro")
    }

    private func buy() {
        guard let product = selectedProduct else { return }
        Task { await pro.purchase(product) }
    }

    /// 자동 갱신 고지. 금액·기간은 상품에서, 해지 방법은 문장으로.
    private var disclosure: some View {
        Text(disclosureText)
            .janjanBody(11)
            .foregroundStyle(Color.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, CGFloat(JanjanSpacing.xs))
    }

    private var disclosureText: String {
        let cancelSentence = t("언제든 설정에서 해지할 수 있어요.", "You can cancel anytime in Settings.")
        switch selectedPlan {
        case .yearly:
            guard let price = pro.yearlyProduct?.displayPrice else { return cancelSentence }
            if pro.isYearlyTrialEligible {
                return t(
                    "7일 무료 체험 후 연 \(price)이 자동으로 결제돼요. \(cancelSentence)",
                    "After a 7-day free trial, \(price) is billed yearly and auto-renews. \(cancelSentence)"
                )
            }
            return t(
                "연 \(price)이 해지할 때까지 자동으로 갱신돼요. \(cancelSentence)",
                "\(price) is billed yearly and auto-renews until cancelled. \(cancelSentence)"
            )
        case .monthly:
            guard let price = pro.monthlyProduct?.displayPrice else { return cancelSentence }
            return t(
                "월 \(price)이 해지할 때까지 자동으로 갱신돼요. \(cancelSentence)",
                "\(price) is billed monthly and auto-renews until cancelled. \(cancelSentence)"
            )
        case .lifetime:
            guard let price = pro.lifetimeProduct?.displayPrice else {
                return t("한 번 결제하면 계속 쓸 수 있어요. 자동 갱신이 없어요.",
                         "Pay once and keep it. Nothing auto-renews.")
            }
            return t(
                "\(price)을 한 번만 결제해요. 자동 갱신이 없어요.",
                "\(price) is billed once. Nothing auto-renews."
            )
        }
    }

    private var links: some View {
        VStack(spacing: CGFloat(JanjanSpacing.s)) {
            HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                Button {
                    Task { await pro.restore() }
                } label: {
                    // 심사자가 가장 먼저 누르는 버튼이다. 몇 초 걸리는 동안
                    // 아무 반응이 없으면 고장 난 것으로 보인다.
                    // `isLoading` 은 상품을 받아오는 동안에도 참이라, 페이월을
                    // 열자마자 몇 초간 "복원하는 중…" 이 떴다(QA 2026-09-22).
                    // 복원이 실제로 도는 동안만 그렇게 말한다.
                    underlined(pro.isRestoring
                               ? t("복원하는 중…", "Restoring…")
                               : t("구매 복원", "Restore purchase"))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(pro.isRestoring)
                .opacity(pro.isRestoring ? 0.5 : 1)

                separator
                externalLink(t("이용약관", "Terms of Use"), Janjan.termsURLString)
                separator
                externalLink(t("개인정보처리방침", "Privacy Policy"), Janjan.privacyPolicyURLString)
            }

            // 평생 이용권에는 기간도 해지도 없다. 여기로 보내면 "구독 없음"
            // 빈 화면을 만난다 - 위 alreadyProCard 는 그것을 알고 문구를
            // 피해 썼는데 이 줄만 남아 있었다(QA 2026-09-19).
            if !pro.hasLifetime {
                externalLink(t("구독 관리", "Manage subscription"), ProProduct.manageSubscriptionsURLString)
            }
        }
        .janjanBody(12)
        .foregroundStyle(Color.ink2)
        .frame(maxWidth: .infinity)
    }

    private var separator: some View {
        Text("·").foregroundStyle(Color.janjan(.line2))
    }

    @ViewBuilder
    private func externalLink(_ title: String, _ urlString: String) -> some View {
        if let url = URL(string: urlString) {
            Link(destination: url) {
                // 12pt 글자 높이(약 15pt)만 눌리면 옆 링크가 대신 열린다.
                // 심사에서 반드시 눌러 보는 자리라 여기부터 44pt 를 지킨다.
                underlined(title)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(Color.ink2)
        }
    }

    private func underlined(_ title: String) -> Text {
        Text(title).underline(true, color: Color.janjan(.line2))
    }

    // MARK: - 상태 카드

    /// 상품을 못 불러왔을 때. 크래시도 빈 화면도 없고, 무료로 계속 쓸 수 있다고 말한다.
    private var storeUnavailableCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(ProStore.storeUnavailableMessage)
                    .janjanBody(14)
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                WhitePillButton(title: t("다시 시도", "Try again"), systemImage: "arrow.clockwise") {
                    pro.load()
                }
            }
        }
    }

    private var loadingCard: some View {
        JanjanCard {
            HStack(spacing: CGFloat(JanjanSpacing.s)) {
                ProgressView()
                Text(t("가격을 불러오는 중이에요.", "Loading prices…"))
                    .janjanBody(14)
                    .foregroundStyle(Color.muted)
            }
        }
    }

    private var alreadyProCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                Text(pro.hasLifetime
                     ? t("평생 이용권으로 Pro 를 쓰고 있어요.", "You're using Pro with the lifetime purchase.")
                     : t("Pro 를 쓰고 있어요.", "You're using Pro."))
                    .janjanBody(15, weight: .medium)
                    .foregroundStyle(Color.ink)
                // 평생권에는 기간도 해지도 없다 - "구독 관리" 로 보내면 빈 화면을 만난다.
                Text(pro.hasLifetime
                     ? t("한 번 결제한 이용권이라 갱신도 해지도 없어요.",
                         "It was a one-time purchase — nothing renews, nothing to cancel.")
                     : t("기간과 해지는 아래 \"구독 관리\" 에서 확인할 수 있어요.",
                         "You can check the period and cancel below under \"Manage subscription.\""))
                    .janjanBody(12)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func errorLine(_ message: String) -> some View {
        Text(message)
            .janjanBody(12)
            .foregroundStyle(Color.janjan(.peachInk))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(CGFloat(JanjanSpacing.s))
            .background(
                RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.row), style: .continuous)
                    .fill(Color.janjan(.peach))
            )
            .onTapGesture { pro.lastError = nil }
            .accessibilityHint(Text(t("눌러서 이 안내를 닫습니다", "Tap to dismiss this notice")))
    }
}

#Preview {
    PaywallView()
        .environmentObject(ProStore())
}
