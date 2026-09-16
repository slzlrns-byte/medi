import SwiftUI
import WatchKit
import JanjanCore

/// 기분 원탭 — 7단계 원 하나 (설계 09절 1층).
/// 고르면 바로 저장되고 닫힌다. 한 줄 덧붙이기는 아이폰에서.
struct MoodQuickView: View {

    @EnvironmentObject private var session: WatchSessionManager
    @Environment(\.dismiss) private var dismiss

    /// 원 사이 간격과 좌우 여백.
    ///
    /// 이전에는 여백 4 에 4열 flexible 그리드였다. 원이 화면 폭을 꽉 채워
    /// 둥근 화면 가장자리에 걸려 잘려 보였고, 3개짜리 둘째 줄은 왼쪽 칸부터
    /// 채워져 쏠려 보였다(사용자 발견 2026-09-16). 여백을 넉넉히 주고
    /// 두 줄을 각각 가운데 정렬한다 - 원 크기는 화면 폭에서 직접 계산해
    /// 4개짜리 줄과 3개짜리 줄이 같은 크기를 쓴다.
    private let spacing: CGFloat = 6
    private let sideMargin: CGFloat = 12

    /// 40mm 부터 울트라까지, 4열이 여백을 두고 들어가는 원 지름.
    private var circleSide: CGFloat {
        let width = WKInterfaceDevice.current().screenBounds.width
        return (width - sideMargin * 2 - spacing * 3) / 4
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    VStack(spacing: spacing) {
                        moodRow(Array(JanjanMood.scores.prefix(4)))
                        moodRow(Array(JanjanMood.scores.dropFirst(4)))
                    }
                    .frame(maxWidth: .infinity)

                    Text(t("−3 매우 힘듦 → +3 좋음", "−3 very hard → +3 good"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, sideMargin)
            }
            .navigationTitle(t("기분", "Mood"))
        }
    }

    private func moodRow(_ scores: [Int]) -> some View {
        HStack(spacing: spacing) {
            ForEach(scores, id: \.self) { score in
                Button {
                    session.send(.mood(score: score, at: Date()))
                    dismiss()
                } label: {
                    Circle()
                        .fill(color(for: score))
                        .frame(width: circleSide, height: circleSide)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(CheckIn.Mood(score).label(session.snapshot.language)))
            }
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
