import SwiftUI
import JanjanCore

/// 가치가 실감 나는 순간에만, 평생 한 번만 놓는 한 줄 (2026-09-19 결정).
///
/// 유도 지점을 세 곳으로 제한하는 원칙(ProGate 주석)의 연장이다. 다른 점은
/// 자물쇠가 아니라 **방금 쓸모가 증명된 순간**에 붙는다는 것 —
///   · 패턴에 처음 그림이 그려질 만큼 기록이 쌓였을 때
///   · 소진 예측의 재료(처방일수·다음 진료일)가 막 갖춰졌을 때
///   · 용량이 실제로 바뀐 바로 그때
///
/// 지키는 규칙:
///   · 팝업이 아니라 카드 안의 한 줄. 손을 막지 않는다.
///   · 한 번 닫으면 그 줄은 다시 나오지 않는다(기기에 기억한다).
///   · 카운트다운·할인·"지금만" 같은 재촉 장치를 두지 않는다.
struct ProMomentNote: View {

    enum Moment: String {
        case patternReady
        case forecastReady
        case doseChangeLogged

        var textKo: String {
            switch self {
            case .patternReady: return "4주 전체 패턴은 Pro 에서 열려요."
            case .forecastReady: return "이 처방으로 다음 진료까지 버틸 수 있는지 계산해 드릴 수 있어요."
            case .doseChangeLogged: return "바꾼 뒤의 기분·수면 변화를 다음 진료까지 모아 볼 수 있어요."
            }
        }

        var textEn: String {
            switch self {
            case .patternReady: return "The full four-week pattern opens with Pro."
            case .forecastReady: return "We can work out whether this prescription lasts until your next visit."
            case .doseChangeLogged: return "You can gather how mood and sleep shift after the change, up to your next visit."
            }
        }

        var text: String { JanjanLanguage.current == .english ? textEn : textKo }

        var defaultsKey: String { "janjan.proMoment.\(rawValue)" }
    }

    let moment: Moment

    @EnvironmentObject private var pro: ProStore
    @State private var isDismissed = false
    @State private var isShowingPaywall = false

    var body: some View {
        if !pro.isPro, !isDismissed, !UserDefaults.standard.bool(forKey: moment.defaultsKey) {
            // 줄 높이는 44pt 닫기 버튼이 정한다. 글자를 .top 으로 붙여 두면
            // 한 줄짜리 안내가 상자 위쪽에 치우쳐 보인다(QA 2026-09-19).
            HStack(alignment: .center, spacing: CGFloat(JanjanSpacing.xs)) {
                Button {
                    isShowingPaywall = true
                } label: {
                    HStack(alignment: .top, spacing: CGFloat(JanjanSpacing.xxs)) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .regular))
                            .padding(.top, 3)
                        Text(moment.text)
                            .janjanBody(12)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(Color.ink2)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button {
                    dismissForGood()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(t("이 안내 닫기", "Dismiss this note")))
            }
            .padding(.horizontal, CGFloat(JanjanSpacing.s))
            .padding(.vertical, CGFloat(JanjanSpacing.xxs))
            .background(
                RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.row), style: .continuous)
                    .fill(Color.janjan(.surface2))
            )
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView()
            }
            .onDisappear {
                // 페이월을 열어 봤다면 할 말은 다 한 것이다. 다음에 또 묻지 않는다.
                if isShowingPaywall { dismissForGood() }
            }
        }
    }

    private func dismissForGood() {
        UserDefaults.standard.set(true, forKey: moment.defaultsKey)
        isDismissed = true
    }
}
