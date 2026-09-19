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
                    title: t("연간 · \(yearly.displayPrice) / 년", "Yearly · \(yearly.displayPrice) / yr"),
                    subtitle: pro.yearlyMonthlyEquivalentText.map { t("월 \($0) 꼴", "≈ \($0) / mo") },
                    tag: pro.isYearlyTrialEligible ? t("7일 무료 체험", "7-day free trial") : nil
                )
            }
            if let monthly = pro.monthlyProduct {
                planCard(
                    plan: .monthly,
                    title: t("월간 · \(monthly.displayPrice) / 월", "Monthly · \(monthly.displayPrice) / mo"),
                    subtitle: nil,
                    tag: nil
                )
            }
            // 평생 이용권(2026-09-19 결정). 구독이 아니라는 것이 이 줄의 핵심 정보라
            // 부제로 또박또박 말한다 - "한 번 결제" 를 크게 파는 화면은 만들지 않는다.
            if let lifetime = pro.lifetimeProduct {
                planCard(
                    plan: .lifetime,
                    title: t("평생 · \(lifetime.displayPrice)", "Lifetime · \(lifetime.displayPrice)"),
                    subtitle: t("한 번 결제 · 구독 아님", "One-time purchase · not a subscription"),
                    tag: nil
                )
            }
        }
    }

    private func planCard(plan: Plan, title: String, subtitle: String?, tag: String?) -> some View {
        let isSelected = selectedPlan == plan

        return Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: CGFloat(JanjanSpacing.s)) {
                radio(isSelected: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .janjanBody(15, weight: .semibold)
                        .foregroundStyle(Color.ink)
                    if let subtitle {
                        Text(subtitle)
                            .janjanBody(11)
                            .foregroundStyle(Color.muted)
                    }
                }

                Spacer(minLength: CGFloat(JanjanSpacing.xs))

                if let tag {
                    Text(tag)
                        .janjanBody(11, weight: .semibold)
                        .foregroundStyle(Color.janjan(.lavInk))
                        .padding(.horizontal, CGFloat(JanjanSpacing.s))
                        .padding(.vertical, CGFloat(JanjanSpacing.xxs) + 1)
                        .background(Capsule(style: .continuous).fill(Color.janjan(.lav)))
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.horizontal, CGFloat(JanjanSpacing.m))
            .padding(.vertical, CGFloat(JanjanSpacing.s) + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.row), style: .continuous)
                    .fill(Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.row), style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.ink : Color.hairline,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
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
            action: buy
        )
    }

    /// 체험을 받을 수 있을 때만 "무료" 라고 쓴다. 못 받는 계정에 무료라고 쓰면 3.1.2 위반이다.
    private var ctaTitle: String {
        if selectedPlan == .yearly, pro.isYearlyTrialEligible {
            return t("7일 무료로 시작하기", "Start 7 days free")
        }
        return t("Pro 시작하기", "Start Pro")
    }

    private func buy() {
        let product: Product?
        switch selectedPlan {
        case .yearly: product = pro.yearlyProduct
        case .monthly: product = pro.monthlyProduct
        case .lifetime: product = pro.lifetimeProduct
        }
        guard let product else { return }
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
                    underlined(t("구매 복원", "Restore purchase"))
                }
                .buttonStyle(.plain)

                separator
                externalLink(t("이용약관", "Terms of Use"), Janjan.termsURLString)
                separator
                externalLink(t("개인정보처리방침", "Privacy Policy"), Janjan.privacyPolicyURLString)
            }

            externalLink(t("구독 관리", "Manage subscription"), ProProduct.manageSubscriptionsURLString)
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
                underlined(title)
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
