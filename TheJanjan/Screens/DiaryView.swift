import SwiftUI
import JanjanCore

/// 기록 — 감정·증상 일기 (설계 03절 · 09절).
///
/// 2층 구조의 1층만 골격으로 세워 두었다. 기분 원 하나를 고르면 저장되고,
/// "한 줄 남길까요?" 가 조용히 펼쳐진다. 2층(감정 단어·수면·활동 태그)은 다음 단계.
struct DiaryView: View {

    @State private var moodScore: Int?
    @State private var noteText: String = ""
    @State private var selectedWords: Set<String> = []

    private let today = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
                    moodCard
                    if moodScore != nil {
                        noteCard
                        emotionWordCard
                    }
                    questionCard
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.bottom, CGFloat(JanjanSpacing.xxl))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle("기록")
        }
    }

    // MARK: - 1층

    private var moodCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("지금 기분은 어떠세요?")
                    .font(JanjanFont.display(22))
                    .foregroundStyle(Color.ink)

                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    ForEach(JanjanMood.scores, id: \.self) { score in
                        Button {
                            moodScore = score
                        } label: {
                            Circle()
                                .fill(Color.mood(score))
                                .frame(width: 38, height: 38)
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color.ink, lineWidth: moodScore == score ? 2 : 0)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(JanjanMood.label(forScore: score)))
                    }
                }

                if let score = moodScore {
                    Text(JanjanMood.label(forScore: score))
                        .font(JanjanFont.body(14, weight: .medium))
                        .foregroundStyle(Color.ink2)
                } else {
                    Text("하나만 골라도 완전한 기록이에요.")
                        .font(JanjanFont.body(13))
                        .foregroundStyle(Color.muted)
                }
            }
        }
    }

    private var noteCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text("한 줄 남길까요?")
                    .font(JanjanFont.body(15, weight: .medium))
                    .foregroundStyle(Color.ink)
                TextField("", text: $noteText, axis: .vertical)
                    .font(JanjanFont.body(15))
                    .lineLimit(1...4)
                    .padding(CGFloat(JanjanSpacing.s))
                    .background(
                        RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.row), style: .continuous)
                            .fill(Color.janjan(.surface2))
                    )
            }
        }
    }

    // MARK: - 2층 맛보기

    private var emotionWordCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("어떤 마음이었어요?")
                    .font(JanjanFont.body(15, weight: .medium))
                    .foregroundStyle(Color.ink)

                // 좋은/나쁜을 색으로 편 가르지 않는다. 전부 같은 회색 칩.
                FlowRow(spacing: CGFloat(JanjanSpacing.xs)) {
                    ForEach(Catalogs.emotions.words.prefix(12)) { word in
                        Button {
                            toggle(word.id)
                        } label: {
                            PillChip(
                                text: word.nameKo,
                                tint: selectedWords.contains(word.id) ? .ink : .surface2,
                                textTint: selectedWords.contains(word.id) ? .surface : .ink2
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if selectedWords.contains(id) {
            selectedWords.remove(id)
        } else {
            selectedWords.insert(id)
        }
    }

    private var questionCard: some View {
        let card = Catalogs.questions.card(for: today)
        return JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text("오늘의 질문")
                    .font(JanjanFont.body(12, weight: .medium))
                    .foregroundStyle(Color.muted)
                Text(card?.textKo ?? "오늘은 그냥 여기까지여도 괜찮아요.")
                    .font(JanjanFont.display(19))
                    .foregroundStyle(Color.ink)
                    .lineSpacing(3)
            }
        }
    }
}

/// 칩을 줄바꿈해 흘려 놓는 아주 작은 레이아웃.
/// iOS 16+ 의 Layout 프로토콜을 쓴다 — 외부 패키지를 들이지 않기 위해.
struct FlowRow: Layout {

    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var origin = CGPoint.zero
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > 0, origin.x + size.width > maxWidth {
                origin.x = 0
                totalHeight += lineHeight + spacing
                lineHeight = 0
            }
            origin.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        totalHeight += lineHeight
        return CGSize(width: maxWidth == .infinity ? origin.x : maxWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

#Preview {
    DiaryView()
}
