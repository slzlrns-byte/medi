import SwiftUI
import JanjanCore

/// 약봉투 스캔 (Pro).
///
/// 사진 → 글자 인식 → **사람이 확인** → 등록 폼. 가운데 확인 단계를 건너뛰지 않는다.
/// 잘못 읽은 약 이름이 조용히 저장되면, 그 뒤의 복약 기록과 재고가 전부 그 위에 쌓인다.
struct PharmacyScanView: View {

    /// 등록이 끝나면 바깥(약 추가 시트)까지 닫는다.
    let onSaved: () -> Void

    @State private var stage: Stage = .intro
    @State private var isShowingCamera = false
    @State private var picked: PharmacyLabelParser.Candidate?

    private enum Stage: Equatable {
        case intro
        case reading
        case results([PharmacyLabelParser.Candidate])
        case nothingFound
    }

    var body: some View {
        ScrollView {
            VStack(spacing: CGFloat(JanjanSpacing.s)) {
                switch stage {
                case .intro:
                    introCard
                case .reading:
                    readingCard
                case .results(let candidates):
                    resultsCards(candidates)
                case .nothingFound:
                    nothingFoundCard
                }

                if stage != .reading {
                    WhitePillButton(
                        title: stage == .intro ? "봉투 찍기" : "다시 찍기",
                        systemImage: "camera"
                    ) {
                        isShowingCamera = true
                    }
                    .padding(.top, CGFloat(JanjanSpacing.xs))
                }

                MedicalDisclaimer()
                    .padding(.horizontal, CGFloat(JanjanSpacing.xxs))
                    .padding(.top, CGFloat(JanjanSpacing.m))
            }
            .padding(.horizontal, CGFloat(JanjanSpacing.m))
            .padding(.top, CGFloat(JanjanSpacing.s))
            .padding(.bottom, CGFloat(JanjanSpacing.xxl))
        }
        .fogBackground()
        .scrollContentBackground(.hidden)
        .navigationTitle(ProFeature.pharmacyScan.titleKo)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                isShowingCamera = false
                guard let image else { return }
                read(image)
            }
            .ignoresSafeArea()
        }
        .navigationDestination(item: $picked) { candidate in
            MedicationFormView(prefill: candidate, onSaved: onSaved)
        }
    }

    // MARK: - 단계별 카드

    private var introCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text("봉투를 평평하게 놓고 찍어 주세요")
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)
                Text("약 이름과 용량이 적힌 면이 보이면 됩니다.")
                    .janjanBody(13)
                    .foregroundStyle(Color.muted)
                Text("사진은 글자를 읽는 동안에만 쓰이고 저장되지 않아요. 읽은 내용은 등록 전에 확인할 수 있어요.")
                    .janjanBody(12)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, CGFloat(JanjanSpacing.xxs))

                if !CameraPicker.isAvailable {
                    Text("이 기기에는 카메라가 없어서 앨범에서 고르게 됩니다.")
                        .janjanBody(12)
                        .foregroundStyle(Color.muted)
                        .padding(.top, CGFloat(JanjanSpacing.xxs))
                }
            }
        }
    }

    private var readingCard: some View {
        JanjanCard {
            HStack(spacing: CGFloat(JanjanSpacing.s)) {
                ProgressView()
                    .tint(Color.ink2)
                Text("글자를 읽고 있어요")
                    .janjanBody(15)
                    .foregroundStyle(Color.ink2)
            }
        }
    }

    private var nothingFoundCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text("약 이름을 찾지 못했어요")
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)
                Text("글자가 흐리거나 접힌 부분에 있으면 잘 안 읽혀요. 다시 찍거나 직접 입력해도 괜찮아요.")
                    .janjanBody(13)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func resultsCards(_ candidates: [PharmacyLabelParser.Candidate]) -> some View {
        VStack(spacing: CGFloat(JanjanSpacing.s)) {
            Text("읽은 내용이 맞는지 확인해 주세요")
                .janjanBody(13)
                .foregroundStyle(Color.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CGFloat(JanjanSpacing.xxs))

            ForEach(candidates) { candidate in
                Button {
                    picked = candidate
                } label: {
                    candidateCard(candidate)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func candidateCard(_ candidate: PharmacyLabelParser.Candidate) -> some View {
        JanjanCard(padding: CGFloat(JanjanSpacing.m)) {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    Text(candidate.name)
                        .janjanBody(16, weight: .medium)
                        .foregroundStyle(Color.ink)
                    if !candidate.strengthText.isEmpty {
                        PillChip(text: candidate.strengthText)
                    }
                    Spacer(minLength: 0)
                }
                // 무엇을 보고 그렇게 읽었는지 함께 보여 준다. 그래야 고칠 수 있다.
                Text(candidate.sourceLine)
                    .janjanBody(12)
                    .foregroundStyle(Color.muted)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - 읽기

    private func read(_ image: UIImage) {
        stage = .reading
        Task {
            let lines = await TextRecognizer.lines(in: image)
            let candidates = PharmacyLabelParser.candidates(from: lines)
            stage = candidates.isEmpty ? .nothingFound : .results(candidates)
        }
    }
}
