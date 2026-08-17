import SwiftUI
import JanjanCore

/// 기분 원탭 — 7단계 원 하나 (설계 09절 1층).
/// 고르면 바로 저장되고 닫힌다. 한 줄 덧붙이기는 아이폰에서.
struct MoodQuickView: View {

    @EnvironmentObject private var session: WatchSessionManager
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 6)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(JanjanMood.scores, id: \.self) { score in
                            Button {
                                session.send(.mood(score: score, at: Date()))
                                dismiss()
                            } label: {
                                Circle()
                                    .fill(color(for: score))
                                    .frame(height: 40)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(JanjanMood.label(forScore: score)))
                        }
                    }

                    Text("−3 매우 힘듦 → +3 좋음")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("기분")
        }
    }

    /// 워치는 시스템 서체·시스템 색을 쓰지만 기분 색만은 폰과 같아야 한다.
    private func color(for score: Int) -> Color {
        let rgb = JanjanMood.color(forScore: score).rgb(for: .dark)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

#Preview {
    MoodQuickView()
        .environmentObject(WatchSessionManager.shared)
}
