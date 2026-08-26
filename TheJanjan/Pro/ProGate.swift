import SwiftUI
import JanjanCore

/// "Pro" 라고 적힌 작은 자물쇠 알약. 색만으로 말하지 않으려고 글자를 함께 둔다.
struct ProBadge: View {

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .regular))
            Text("Pro")
                .janjanBody(11, weight: .semibold)
        }
        .foregroundStyle(Color.janjan(.lavInk))
        .padding(.horizontal, CGFloat(JanjanSpacing.xs))
        .padding(.vertical, CGFloat(JanjanSpacing.xxs) - 1)
        .background(Capsule(style: .continuous).fill(Color.janjan(.lav)))
        .accessibilityHidden(true)
    }
}

/// Pro 기능 앞에 놓는 얇은 문. 구독 중이면 아무 일도 하지 않고,
/// 아니면 자물쇠 알약을 얹고 눌렀을 때 원래 동작 대신 페이월을 올린다.
///
/// 유도는 설계에서 정한 세 곳에서만 쓴다(약 추가의 스캔 · 리포트 · 워치 첫 실행).
/// 홈 배너·팝업·카운트다운은 만들지 않는다.
struct ProGate: ViewModifier {

    let feature: ProFeature

    @EnvironmentObject private var pro: ProStore
    @State private var isShowingPaywall = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if !pro.isPro {
                    ProBadge()
                        .offset(x: CGFloat(JanjanSpacing.xs), y: -CGFloat(JanjanSpacing.s))
                }
            }
            .overlay {
                if !pro.isPro {
                    // 아래 버튼이 눌리는 대신 페이월이 열린다. 잠긴 기능이 반쯤 동작해서
                    // "고장난 것처럼" 보이는 경로를 만들지 않는다.
                    Button {
                        isShowingPaywall = true
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(feature.titleKo) — Pro 기능"))
                    .accessibilityHint(Text("눌러서 Pro 를 알아봅니다"))
                }
            }
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView()
            }
    }
}

extension View {

    /// Pro 기능임을 표시하고, 무료 사용자가 누르면 페이월을 올린다.
    func proGated(_ feature: ProFeature) -> some View {
        modifier(ProGate(feature: feature))
    }
}

#Preview {
    VStack(spacing: 24) {
        ProBadge()

        WhitePillButton(title: "PDF 로 내보내기", systemImage: "square.and.arrow.up") {}
            .proGated(.reports)
    }
    .padding(40)
    .fogBackground()
    .environmentObject(ProStore())
}
