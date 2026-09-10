import SwiftUI
import JanjanCore

/// 기분 원탭 — 7단계 원 하나 (설계 09절 1층).
/// 고르면 바로 저장되고 닫힌다. 한 줄 덧붙이기는 아이폰에서.
struct MoodQuickView: View {

    @EnvironmentObject private var session: WatchSessionManager
    @Environment(\.dismiss) private var dismiss

    /// 4열 고정. adaptive(minimum: 40) 은 40mm 워치에서 3열로 줄바꿈되어
    /// 일곱 번째 원이 혼자 남고 아래 설명까지 밀어냈다. 열 수를 못박고
    /// 원이 폭에 맞춰 줄어들게 한다 - 4+3 은 어느 크기에서도 4+3 이다.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

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
                                    .aspectRatio(1, contentMode: .fit)
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
    /// 테마도 폰이 스냅샷에 실어 보낸 것을 그대로 따른다.
    private func color(for score: Int) -> Color {
        let rgb = JanjanMood.color(forScore: score)
            .rgb(for: .dark, theme: session.snapshot.theme)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

#Preview {
    MoodQuickView()
        .environmentObject(WatchSessionManager.shared)
}
