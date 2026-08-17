import SwiftUI
import JanjanCore

/// 오늘 — 허브 화면.
///
/// 아직 저장소와 연결되지 않은 골격이다. 예시 데이터로 시각 언어를 먼저 굳혀 두고,
/// 실제 SwiftData 질의는 화면 구조가 확정된 뒤에 끼운다.
struct TodayView: View {

    @Binding var isShowingSettings: Bool

    // 저장 프로퍼티로 두면 private 때문에 memberwise 초기화 함수가 private 이 되어
    // 다른 파일에서 TodayView(isShowingSettings:) 를 부를 수 없다. 계산 프로퍼티로 둔다.
    private var today: Date { Date() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
                    hero
                    slotSection
                    checkInCard
                    glanceCard
                    MedicalDisclaimer()
                        .padding(.horizontal, CGFloat(JanjanSpacing.xxs))
                        .padding(.top, CGFloat(JanjanSpacing.xs))
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.bottom, CGFloat(JanjanSpacing.xxl))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Color.ink2)
                    }
                    .accessibilityLabel(Text("설정"))
                }
            }
        }
    }

    // MARK: - 인사

    private var hero: some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
            Text(greetingKo)
                .font(JanjanFont.display(32))
                .foregroundStyle(Color.ink)
                .lineSpacing(4)
            Text(subtitleKo)
                .font(JanjanFont.body(15))
                .foregroundStyle(Color.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, CGFloat(JanjanSpacing.xs))
        .padding(.bottom, CGFloat(JanjanSpacing.xxs))
    }

    private var greetingKo: String {
        let hour = Calendar.current.component(.hour, from: today)
        switch hour {
        case 5..<11: return "좋은 아침이에요"
        case 11..<17: return "오후예요"
        case 17..<22: return "저녁이에요"
        default: return "늦은 시간이네요"
        }
    }

    private var subtitleKo: String {
        let pending = slots.filter { !$0.isCompleted }.count
        if pending == 0 { return "오늘 약은 다 챙기셨어요." }
        return "오늘 남은 시간대가 \(pending)번 있어요."
    }

    // MARK: - 시간대 타일

    private struct SlotLine: Identifiable {
        let id: String
        let slot: DoseSlot
        let time: TimeOfDay
        let medications: [Medication]
        let isCompleted: Bool
        let tint: JanjanColor
    }

    private var slots: [SlotLine] {
        let grouped = Dictionary(grouping: SampleData.schedules, by: { $0.slot.storageKey })

        return grouped.compactMap { key, schedules -> SlotLine? in
            guard let slot = DoseSlot(storageKey: key), let first = schedules.first else { return nil }
            let medications = schedules.compactMap { SampleData.medication(id: $0.medicationID) }
            return SlotLine(
                id: key,
                slot: slot,
                time: first.timeOfDay,
                medications: medications,
                isCompleted: slot == .morning,
                tint: tint(for: slot)
            )
        }
        .sorted { $0.slot.sortKey < $1.slot.sortKey }
    }

    private func tint(for slot: DoseSlot) -> JanjanColor {
        switch slot {
        case .morning: return JanjanSemanticColor.morning
        case .noon: return .surface2
        case .evening: return JanjanSemanticColor.taken
        case .bedtime, .custom: return JanjanSemanticColor.night
        }
    }

    private var slotSection: some View {
        VStack(spacing: CGFloat(JanjanSpacing.s)) {
            ForEach(slots) { line in
                slotTile(line)
            }
        }
    }

    private func slotTile(_ line: SlotLine) -> some View {
        JanjanTile(tint: line.tint, padding: CGFloat(JanjanSpacing.m)) {
            HStack(alignment: .center, spacing: CGFloat(JanjanSpacing.s)) {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                    HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                        Text(line.slot.labelKo)
                            .font(JanjanFont.display(22))
                            .foregroundStyle(Color.ink)
                        Text(line.time.description)
                            .font(JanjanFont.body(13))
                            .foregroundStyle(Color.ink2)
                    }
                    Text(line.medications.map(\.name).joined(separator: " · "))
                        .font(JanjanFont.body(14))
                        .foregroundStyle(Color.ink2)
                        .lineLimit(2)
                }

                Spacer(minLength: CGFloat(JanjanSpacing.xs))

                // 색만으로 상태를 말하지 않는다. 글자가 항상 함께 온다.
                PillChip(
                    text: line.isCompleted ? "완료" : "남음",
                    tint: .surface,
                    textTint: line.isCompleted ? .sageInk : .ink2
                )
            }
        }
    }

    // MARK: - 체크인

    private var checkInCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("오늘 기분")
                    .font(JanjanFont.display(20))
                    .foregroundStyle(Color.ink)
                Text("하나만 골라도 괜찮아요. 나머지는 나중에 덧붙일 수 있어요.")
                    .font(JanjanFont.body(13))
                    .foregroundStyle(Color.muted)

                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    ForEach(JanjanMood.scores, id: \.self) { score in
                        Circle()
                            .fill(Color.mood(score))
                            .frame(width: 34, height: 34)
                            .accessibilityLabel(Text(JanjanMood.label(forScore: score)))
                    }
                }
                .padding(.top, CGFloat(JanjanSpacing.xxs))
            }
        }
    }

    // MARK: - 한눈에

    private var glanceCard: some View {
        let prescription = SampleData.prescription(referenceDate: today)
        let daysUntilVisit = prescription.daysUntilNextVisit(from: today) ?? 0

        return JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("한눈에")
                    .font(JanjanFont.display(20))
                    .foregroundStyle(Color.ink)

                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    PillChip(text: "다음 진료 D-\(max(daysUntilVisit, 0))", tint: .surface2)
                    PillChip(text: "부족한 약 없음", tint: .surface2)
                }
            }
        }
    }
}

#Preview {
    TodayView(isShowingSettings: .constant(false))
}
