import SwiftUI
import JanjanCore

/// 약 모양으로 찾기 (Pro).
///
/// 모양·색·각인을 골라 낱알 데이터에서 후보를 좁힌다. **단정하지 않는다** —
/// 결과 머리에는 늘 "이 약으로 추측됩니다" 와 "정확한 것은 의사나 약사에게
/// 확인해 주세요" 가 함께 붙는다. 하얀 원형 정제는 서로 너무 닮아서,
/// 여기서 고른 이름이 틀렸을 때의 값이 다른 화면보다 훨씬 크다.
///
/// 검색은 전부 기기 안에서 한다 - 번들에 실린 데이터만 뒤지고,
/// 무엇을 찾았는지는 기기 밖으로 나가지 않는다.
struct PillFinderView: View {

    let onSaved: () -> Void

    @State private var shape: PillFinder.Shape?
    @State private var color: PillFinder.PillColor?
    @State private var imprint = ""
    @State private var picked: PharmacyLabelParser.Candidate?

    private var lang: JanjanLanguage { .current }

    private var query: PillFinder.Query {
        PillFinder.Query(shape: shape, color: color, imprint: imprint)
    }

    private var results: [PillFinder.Pill] {
        PillFinder.search(query, in: PillCatalog.pills)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: CGFloat(JanjanSpacing.s)) {
                filterCard
                resultsSection

                // 공공누리 제1유형(출처표시) - 데이터를 쓰는 조건이다.
                if !PillCatalog.pills.isEmpty {
                    Text(t(
                        "출처: 식품의약품안전처 의약품 낱알식별 정보",
                        "Source: MFDS (Korea) pill identification data"
                    ))
                    .janjanBody(11)
                    .foregroundStyle(Color.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, CGFloat(JanjanSpacing.m))
            .padding(.top, CGFloat(JanjanSpacing.s))
            .padding(.bottom, CGFloat(JanjanSpacing.xxl))
        }
        .fogBackground()
        .scrollContentBackground(.hidden)
        .navigationTitle(t("약 모양으로 찾기", "Find by appearance"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $picked) { candidate in
            MedicationFormView(prefill: candidate, onSaved: onSaved)
        }
    }

    // MARK: - 조건 고르기

    private var filterCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                    Text(t("모양", "Shape"))
                        .janjanBody(12, weight: .medium)
                        .foregroundStyle(Color.muted)
                    FlowRow(spacing: CGFloat(JanjanSpacing.xs)) {
                        ForEach(PillFinder.Shape.allCases, id: \.self) { candidate in
                            TogglePill(text: candidate.label(lang), isOn: shape == candidate) {
                                shape = (shape == candidate) ? nil : candidate
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                    Text(t("색", "Color"))
                        .janjanBody(12, weight: .medium)
                        .foregroundStyle(Color.muted)
                    FlowRow(spacing: CGFloat(JanjanSpacing.xs)) {
                        ForEach(PillFinder.PillColor.allCases, id: \.self) { candidate in
                            TogglePill(text: candidate.label(lang), isOn: color == candidate) {
                                color = (color == candidate) ? nil : candidate
                            }
                        }
                    }
                }

                JanjanField(
                    label: t("각인 (선택)", "Imprint (optional)"),
                    placeholder: t("예: GD 10", "e.g. GD 10"),
                    text: $imprint
                )
                Text(t(
                    "알약에 새겨진 글자·숫자예요. 띄어쓰기나 대소문자는 달라도 괜찮아요.",
                    "The letters or numbers printed on the pill. Spacing and case don't matter."
                ))
                .janjanBody(12)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 결과

    @ViewBuilder
    private var resultsSection: some View {
        if query.isEmpty {
            JanjanCard {
                Text(t(
                    "모양이나 색을 고르면 여기에서 후보를 찾아 드려요.",
                    "Pick a shape or color and candidates will appear here."
                ))
                .janjanBody(13)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if PillCatalog.pills.isEmpty {
            JanjanCard {
                Text(t(
                    "낱알 데이터가 아직 이 판에 실려 있지 않아요.",
                    "Pill appearance data isn't included in this build yet."
                ))
                .janjanBody(13)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if results.isEmpty {
            JanjanCard {
                Text(t(
                    "조건에 맞는 약을 찾지 못했어요. 조건을 하나 줄여 보세요.",
                    "No match for these filters. Try removing one."
                ))
                .janjanBody(13)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text(t("이 약으로 추측됩니다", "These are our best guesses"))
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)
                Text(t(
                    "겉모습이 같은 다른 약이 있을 수 있어요. 정확한 것은 의사나 약사에게 확인해 주세요.",
                    "Different medications can look the same. Please confirm with your doctor or pharmacist."
                ))
                .janjanBody(13)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)

                Text(t(
                    "낱알 사진은 식약처 서버에서 그때그때 불러오고, 기기에 저장하지 않아요.",
                    "Pill photos load from the MFDS server on demand and aren't stored on this device."
                ))
                .janjanBody(12)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)

                ForEach(results) { pill in
                    resultCard(pill)
                }

                if results.count == PillFinder.maxResults {
                    Text(t(
                        "후보가 많아 \(PillFinder.maxResults)개까지만 보여요. 각인을 넣으면 더 좁혀져요.",
                        "Showing the first \(PillFinder.maxResults). Add an imprint to narrow it down."
                    ))
                    .janjanBody(12)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func resultCard(_ pill: PillFinder.Pill) -> some View {
        Button {
            // 스캔 후보와 같은 길로 폼에 채워만 둔다 - 사용자가 보고 고칠 수 있다.
            picked = PharmacyLabelParser.Candidate(
                name: pill.name,
                strengthText: pill.strengthText,
                sourceLine: appearanceLine(pill)
            )
        } label: {
            JanjanCard(padding: CGFloat(JanjanSpacing.m)) {
                HStack(alignment: .top, spacing: CGFloat(JanjanSpacing.s)) {
                    // 사진은 식약처 서버에서 그때그때 불러온다(핫링크).
                    // 파일을 받아 앱에 담지 않는다 - 촬영물의 재배포 권리가
                    // 완전히 정리되지 않은 회색지대라서다(결정 로그 참고).
                    // 사진이 없거나 아직 안 왔어도 글만으로 성립해야 한다.
                    if let urlString = pill.imageURLString, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFit()
                            } else {
                                Color.janjan(.surface2)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                        HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                            Text(pill.name)
                                .janjanBody(16, weight: .medium)
                                .foregroundStyle(Color.ink)
                                .lineLimit(1)
                            if !pill.strengthText.isEmpty {
                                PillChip(text: pill.strengthText)
                            }
                            Spacer(minLength: 0)
                        }
                        // 무엇을 보고 추측했는지 함께 보인다 - 그래야 아니라고 판단할 수 있다.
                        Text(appearanceLine(pill))
                            .janjanBody(12)
                            .foregroundStyle(Color.muted)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// "원형 · 하양 · 각인 GD 10" 처럼 겉모습을 한 줄로.
    private func appearanceLine(_ pill: PillFinder.Pill) -> String {
        var parts = [pill.shape.label(lang), pill.colorFront.label(lang)]
        if let back = pill.colorBack, back != pill.colorFront {
            parts[1] = "\(pill.colorFront.label(lang))/\(back.label(lang))"
        }
        let imprint = [pill.imprintFront, pill.imprintBack]
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        if !imprint.isEmpty {
            parts.append(t("각인 \(imprint)", "Imprint \(imprint)"))
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        PillFinderView {}
    }
}
