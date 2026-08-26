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
            Text(Janjan.appNameKo)
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
                .accessibilityLabel(Text("닫기"))

                Spacer()
            }
        }
        .frame(height: 36)
    }

    private var headline: some View {
        Text("더 잔잔한 하루를 위해,\nPro")
            .janjanDisplay(30, relativeTo: .largeTitle)
            .foregroundStyle(Color.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 라벤더 타일 안에 출시 시점 Pro 4줄. 문구는 JanjanCore 가 들고 있다.
    private var featureCard: some View {
        JanjanTile(tint: .lav, padding: CGFloat(JanjanSpacing.xl)) {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xl)) {
                ForEach(ProFeature.launchHighlights, id: \.self) { feature in
                    HStack(spacing: CGFloat(JanjanSpacing.s)) {
                        CircleGlyph(
                            systemImage: "checkmark",
                            background: .surface,
                            foreground: .lavInk,
                            diameter: 22
                        )
                        Text(feature.titleKo)
                            .janjanBody(16, weight: .medium)
                            .foregroundStyle(Color.ink)
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

            Text("무료 기능은 구독 없이 계속 쓸 수 있어요.")
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
                    title: "연간 · \(yearly.displayPrice) / 년",
                    subtitle: pro.yearlyMonthlyEquivalentText.map { "월 \($0) 꼴" },
                    tag: pro.isYearlyTrialEligible ? "7일 무료 체험" : nil
                )
            }
            if let monthly = pro.monthlyProduct {
                planCard(
                    plan: .monthly,
                    title: "월간 · \(monthly.displayPrice) / 월",
                    subtitle: nil,
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
            return "7일 무료로 시작하기"
        }
        return "Pro 시작하기"
    }

    private func buy() {
        let product: Product? = selectedPlan == .yearly ? pro.yearlyProduct : pro.monthlyProduct
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
        let cancelSentence = "언제든 설정에서 해지할 수 있어요."
        switch selectedPlan {
        case .yearly:
            guard let price = pro.yearlyProduct?.displayPrice else { return cancelSentence }
            if pro.isYearlyTrialEligible {
                return "7일 무료 체험 후 연 \(price)이 자동으로 결제돼요. \(cancelSentence)"
            }
            return "연 \(price)이 해지할 때까지 자동으로 갱신돼요. \(cancelSentence)"
        case .monthly:
            guard let price = pro.monthlyProduct?.displayPrice else { return cancelSentence }
            return "월 \(price)이 해지할 때까지 자동으로 갱신돼요. \(cancelSentence)"
        }
    }

    private var links: some View {
        VStack(spacing: CGFloat(JanjanSpacing.s)) {
            HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                Button {
                    Task { await pro.restore() }
                } label: {
                    underlined("구매 복원")
                }
                .buttonStyle(.plain)

                separator
                externalLink("이용약관", Janjan.termsURLString)
                separator
                externalLink("개인정보처리방침", Janjan.privacyPolicyURLString)
            }

            externalLink("구독 관리", ProProduct.manageSubscriptionsURLString)
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
                Text(ProStore.storeUnavailableMessageKo)
                    .janjanBody(14)
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                WhitePillButton(title: "다시 시도", systemImage: "arrow.clockwise") {
                    pro.load()
                }
                .overlay(
                    Capsule(style: .continuous).strokeBorder(Color.hairline, lineWidth: 1)
                )
            }
        }
    }

    private var loadingCard: some View {
        JanjanCard {
            HStack(spacing: CGFloat(JanjanSpacing.s)) {
                ProgressView()
                Text("가격을 불러오는 중이에요.")
                    .janjanBody(14)
                    .foregroundStyle(Color.muted)
            }
        }
    }

    private var alreadyProCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                Text("Pro 를 쓰고 있어요.")
                    .janjanBody(15, weight: .medium)
                    .foregroundStyle(Color.ink)
                Text("기간과 해지는 아래 \"구독 관리\" 에서 확인할 수 있어요.")
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
            .accessibilityHint(Text("눌러서 이 안내를 닫습니다"))
    }
}

#Preview {
    PaywallView()
        .environmentObject(ProStore())
}
