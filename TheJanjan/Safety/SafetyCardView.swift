import SwiftUI
import JanjanCore

/// 안전 카드 (2026-08-17 결정).
///
/// 무엇을 하지 않는지가 이 화면의 전부다.
///   · 판단하지 않는다 — "위험", "즉시", "심각" 같은 말이 한 마디도 없다.
///   · 막지 않는다 — 기록은 이미 저장됐고 이 카드는 그 뒤에 조용히 올라온다.
///   · 붙잡지 않는다 — 닫기는 언제나 열려 있고, 닫아도 아무 일도 일어나지 않는다.
///
/// 왜 올라왔는지(증상 때문인지, 이어진 기분 때문인지)는 문구를 바꾸지 않는다.
/// 어느 쪽이든 사용자에게 필요한 것은 같기 때문이다.
struct SafetyCardView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let contacts = Janjan.crisisContactsForCurrentRegion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
                    Text(contacts.isEmpty
                         ? Janjan.safetyCardWithoutContactsKo
                         : Janjan.safetyCardMessageKo)
                        .janjanDisplay(22)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(contacts) { contact in
                        contactCard(contact)
                    }

                    Text("응급 상황은 112 · 119.")
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)

                    MedicalDisclaimer()
                        .padding(.top, CGFloat(JanjanSpacing.s))
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.top, CGFloat(JanjanSpacing.m))
                .padding(.bottom, CGFloat(JanjanSpacing.xxl))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func contactCard(_ contact: Janjan.CrisisContact) -> some View {
        Button {
            call(contact)
        } label: {
            JanjanCard(padding: CGFloat(JanjanSpacing.m)) {
                HStack(spacing: CGFloat(JanjanSpacing.s)) {
                    CircleGlyph(systemImage: "phone", background: .sage, foreground: .sageInk)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.titleKo)
                            .janjanBody(16, weight: .medium)
                            .foregroundStyle(Color.ink)
                        Text(contact.subtitleKo)
                            .janjanBody(12)
                            .foregroundStyle(Color.muted)
                    }
                    Spacer(minLength: CGFloat(JanjanSpacing.xs))
                    Text(contact.number)
                        .janjanBody(16, weight: .medium)
                        .foregroundStyle(Color.ink2)
                        .monospacedDigit()
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(contact.titleKo) \(contact.number) 에 전화하기"))
    }

    private func call(_ contact: Janjan.CrisisContact) {
        guard let url = URL(string: "tel://\(contact.dialDigits)") else { return }
        openURL(url)
    }
}

#Preview {
    Color.fog
        .sheet(isPresented: .constant(true)) { SafetyCardView() }
}
