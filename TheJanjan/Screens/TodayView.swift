import SwiftUI
import SwiftData
import JanjanCore

/// 오늘 — 허브 화면 (설계 03절).
///
/// 화면은 아무것도 계산하지 않는다. 하루 계획은 `DayPlan`, 재고는 `InventoryCalculator`,
/// 저장은 `DoseRecorder` · `CheckInRecorder` 가 한다. 여기 있는 것은 그리기와 탭뿐이다.
struct TodayView: View {

    @Binding var isShowingSettings: Bool

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var pro: ProStore

    // v1 의 기록량(하루 몇 건 × 1년)에서는 통째로 읽어도 부담이 없고,
    // 재고는 마지막 정정 이후 전부를 봐야 하므로 기간으로 자르면 오히려 틀린다.
    // 기록이 몇 해치 쌓여 느려지면 그때 재고 기준점을 캐시하는 쪽으로 옮긴다.
    @Query(sort: \MedicationRecord.createdAt) private var medicationRecords: [MedicationRecord]
    @Query private var scheduleRecords: [ScheduleRecord]
    @Query private var doseRecords: [DoseEventRecord]
    @Query private var stockRecords: [StockEventRecord]
    @Query private var checkInRecords: [CheckInRecord]
    @Query(sort: \PrescriptionRecord.visitDate, order: .reverse)
    private var prescriptionRecords: [PrescriptionRecord]

    @State private var openSlot: SlotSelection?
    @State private var safetyReason: SafetyReason?

    /// 시트에 넘길 때 Identifiable 이 필요해 감싼다.
    private struct SafetyReason: Identifiable {
        let id = UUID()
        let reason: SafetyTrigger.Reason
    }

    /// 시트에는 값이 아니라 열쇠만 들고 간다. 값을 들고 가면 기록한 뒤에도
    /// 시트가 기록 전의 옛 줄을 계속 보여 준다.
    private struct SlotSelection: Identifiable { let id: String }

    private var today: Date { Date() }

    // MARK: - 저장소에서 읽어 온 것

    private var medications: [Medication] { medicationRecords.map(\.core) }
    private var schedules: [Schedule] { scheduleRecords.map(\.core) }
    private var doseEvents: [DoseEvent] { doseRecords.map(\.core) }
    private var stockEvents: [StockEvent] { stockRecords.map(\.core) }

    private var plan: [DayPlan.SlotLine] {
        DayPlan.slots(
            on: today,
            schedules: schedules,
            medications: medications,
            doseEvents: doseEvents
        )
    }

    private var todaysMoodScore: Int? {
        let calendar = Calendar.current
        return checkInRecords
            .first { calendar.isDate($0.date, inSameDayAs: today) }?
            .moodScore
    }

    private var hasAnyMedication: Bool { !medicationRecords.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
                    hero
                    if hasAnyMedication {
                        slotSection
                    } else {
                        emptyCard
                    }
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
            .sheet(item: $safetyReason) { _ in
                SafetyCardView()
            }
            .sheet(item: $openSlot) { selection in
                if let line = plan.first(where: { $0.slotKey == selection.id }) {
                    SlotRecordSheet(line: line) { entry, status in
                        record(entry, in: line, as: status)
                    }
                } else {
                    // 시트를 열어 둔 사이에 그 시간대가 사라질 수 있다(다른 기기에서
                    // 약을 중단하거나 지웠을 때). 빈 시트를 남기지 않고 이유를 말한다.
                    SlotGoneSheet()
                }
            }
        }
    }

    // MARK: - 인사

    private var hero: some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
            Text(greetingKo)
                .janjanDisplay(32)
                .foregroundStyle(Color.ink)
            Text(subtitleKo)
                .janjanBody(15)
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

    /// 한 문장에 한 정보. 놓쳤다고 다그치지 않고 남은 것만 알린다.
    private var subtitleKo: String {
        guard hasAnyMedication else { return "약을 등록하면 여기에 오늘 일정이 보여요." }
        let pending = DayPlan.pendingSlotCount(in: plan)
        if plan.isEmpty { return "오늘은 예정된 약이 없어요." }
        if pending == 0 { return "오늘 약은 다 챙기셨어요." }
        return "오늘 남은 시간대가 \(pending)번 있어요."
    }

    // MARK: - 시간대 타일

    private var slotSection: some View {
        VStack(spacing: CGFloat(JanjanSpacing.s)) {
            ForEach(plan) { line in
                slotTile(line)
            }
        }
    }

    /// 그 시간대에 아직 답하지 않은 것을 전부 복용함으로 적는다.
    ///
    /// 이 앱에서 가장 자주 하는 동작이라 가장 싸야 한다. 예전에는 타일을 눌러
    /// 시트를 열고, 약마다 복용함을 누르고, 닫아야 했다 - 하루 두 번이면
    /// 한 달에 180번이다.
    ///
    /// 이미 건너뜀으로 적어 둔 것은 건드리지 않는다. 사용자가 일부러 고른 답을
    /// 한 번의 손짓이 조용히 덮으면 안 된다.
    private func recordRestTaken(in line: DayPlan.SlotLine) {
        for entry in line.entries where entry.status == nil || entry.status == .unrecorded {
            record(entry, in: line, as: .taken)
        }
    }

    private func tint(for slot: DoseSlot) -> JanjanColor {
        switch slot {
        case .morning: return JanjanSemanticColor.morning
        case .noon: return .surface2
        case .evening: return JanjanSemanticColor.taken
        case .bedtime, .custom: return JanjanSemanticColor.night
        }
    }

    /// 타일 하나에 손잡이가 둘이다.
    ///
    /// 오른쪽 '먹었어요' 는 한 번에 그 시간대를 끝낸다. 왼쪽 본문은 예전처럼
    /// 시트를 열어 약마다 따로 답하게 한다. 자주 하는 쪽이 크고 가깝고,
    /// 드문 쪽(하나만 건너뛰기, 되돌리기)이 한 겹 안에 있다.
    private func slotTile(_ line: DayPlan.SlotLine) -> some View {
        JanjanTile(tint: tint(for: line.slot), padding: CGFloat(JanjanSpacing.m)) {
            HStack(alignment: .center, spacing: CGFloat(JanjanSpacing.s)) {
                Button {
                    openSlot = SlotSelection(id: line.slotKey)
                } label: {
                    VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                        HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                            Text(line.slot.labelKo)
                                .janjanDisplay(22)
                                .foregroundStyle(Color.ink)
                            Text(line.time.description)
                                .janjanBody(13)
                                .foregroundStyle(Color.ink2)
                        }
                        Text(line.medicationNames.joined(separator: " · "))
                            .janjanBody(14)
                            .foregroundStyle(Color.ink2)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("약마다 따로 기록합니다"))

                if line.isCompleted {
                    // 색만으로 상태를 말하지 않는다. 글자가 항상 함께 온다.
                    // 높이는 아래 버튼과 맞춘다 - 다르면 다 적은 순간 타일이 튄다.
                    PillChip(text: "완료", tint: .surface, textTint: .sageInk)
                        .frame(minWidth: 96, minHeight: 56)
                } else {
                    Button {
                        recordRestTaken(in: line)
                    } label: {
                        VStack(spacing: 2) {
                            Text("먹었어요")
                                .janjanBody(15, weight: .medium)
                                .foregroundStyle(Color.ink)
                            Text("\(line.pendingCount)개")
                                .janjanBody(12)
                                .foregroundStyle(Color.ink2)
                        }
                        .padding(.horizontal, CGFloat(JanjanSpacing.m))
                        .padding(.vertical, CGFloat(JanjanSpacing.s))
                        .frame(minWidth: 96, minHeight: 56)
                        .background(
                            Capsule(style: .continuous).fill(Color.surface)
                        )
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(line.slot.labelKo) 약 \(line.pendingCount)개 먹었어요"))
                    .accessibilityHint(Text("한 번에 기록합니다"))
                }
            }
        }
    }

    private var emptyCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text("아직 등록한 약이 없어요")
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)
                Text("약 탭에서 하나만 추가해도 오늘 일정이 만들어져요.")
                    .janjanBody(13)
                    .foregroundStyle(Color.muted)
            }
        }
    }

    // MARK: - 체크인

    private var checkInCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("오늘 기분")
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)
                Text(todaysMoodScore == nil
                     ? "하나만 골라도 괜찮아요. 나머지는 나중에 덧붙일 수 있어요."
                     : "언제든 다시 고를 수 있어요.")
                    .janjanBody(13)
                    .foregroundStyle(Color.muted)

                MoodPickerRow(chosenScore: todaysMoodScore) { recordMood($0) }
                    .padding(.top, CGFloat(JanjanSpacing.xxs))
            }
        }
    }

    // MARK: - 한눈에

    private var glanceCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("한눈에")
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)

                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    PillChip(text: nextVisitText, tint: .surface2)
                    // 소진 예측은 Pro. 무료에서는 자리만 비우고 조르지 않는다 —
                    // 유도 지점은 설계가 정한 세 곳뿐이고 여기는 그 중 하나가 아니다.
                    if pro.isPro, let text = shortfallText {
                        PillChip(text: text, tint: .surface2)
                    }
                }
            }
        }
    }

    private var nextVisitText: String {
        guard let days = prescriptionRecords
            .compactMap({ $0.core.daysUntilNextVisit(from: today) })
            .filter({ $0 >= 0 })
            .min()
        else { return "다음 진료 미정" }
        return days == 0 ? "오늘 진료" : "다음 진료 D-\(days)"
    }

    /// 다음 진료 전에 모자라는 약을 약별로 세지 않고 한 번에 묶어 말한다(설계 05절).
    private var shortfallText: String? {
        guard let nextVisit = prescriptionRecords
            .compactMap({ $0.core.nextVisitDate })
            .filter({ $0 >= today })
            .min()
        else { return nil }

        let short = medications.filter { medication in
            let snapshot = InventoryCalculator.snapshot(
                medicationID: medication.id,
                schedules: schedules,
                stockEvents: stockEvents,
                doseEvents: doseEvents,
                nextVisit: nextVisit,
                asOf: today
            )
            return (snapshot.shortfallDays ?? 0) > 0
        }

        guard !short.isEmpty else { return "부족한 약 없음" }
        if short.count == 1 { return "\(short[0].name) 모자람" }
        return "모자라는 약 \(short.count)개"
    }

    // MARK: - 기록

    private func record(_ entry: DayPlan.Entry, in line: DayPlan.SlotLine, as status: DoseEvent.Status) {
        DoseRecorder.record(
            medicationID: entry.medicationID,
            slotKey: line.slotKey,
            status: status,
            source: .phone,
            on: today,
            quantity: entry.dose,
            in: context
        )
        save()
    }

    /// 오늘 화면에서도 기분을 고를 수 있으므로 안전 카드 판단이 여기에도 있어야 한다.
    /// 판단 자체는 기록 탭과 같은 `SafetyTrigger` 가 한다.
    private func recordMood(_ score: Int) {
        let saved = CheckInRecorder.recordMood(score: score, on: today, in: context)
        save()

        var checkIns = checkInRecords
            .filter { !Calendar.current.isDate($0.date, inSameDayAs: today) }
            .map(\.core)
        checkIns.append(saved.core)

        if let reason = SafetyTrigger.reason(forCheckIns: checkIns, endingAt: today) {
            safetyReason = SafetyReason(reason: reason)
        }
    }

    private func save() {
        try? context.save()
        // 폰에서 기록했으니 워치 화면도 따라오게 한다.
        AppServices.shared.pushWatchSnapshot()
    }
}

/// 열어 둔 사이에 그 시간대가 사라졌을 때.
private struct SlotGoneSheet: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: CGFloat(JanjanSpacing.m)) {
            Text("이 시간대가 지금은 없어요")
                .janjanDisplay(22)
                .foregroundStyle(Color.ink)
            Text("다른 기기에서 약이 바뀌었을 수 있어요.")
                .janjanBody(14)
                .foregroundStyle(Color.muted)
            WhitePillButton(title: "닫기") { dismiss() }
        }
        .padding(CGFloat(JanjanSpacing.l))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fogBackground()
        .presentationDetents([.medium])
    }
}

/// 한 시간대를 펼쳐 약마다 답을 받는 시트.
///
/// "모두 복용함" 을 위에 두되, 약마다 따로 고를 수 있게 남겨 둔다.
/// 건너뜀도 정상적인 선택이라 복용함과 같은 크기·같은 무게로 놓는다.
private struct SlotRecordSheet: View {

    let line: DayPlan.SlotLine
    let onRecord: (DayPlan.Entry, DoseEvent.Status) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CGFloat(JanjanSpacing.s)) {
                    ForEach(line.entries) { entry in
                        entryCard(entry)
                    }

                    if line.entries.count > 1 {
                        WhitePillButton(title: "모두 복용함", systemImage: "checkmark") {
                            for entry in line.entries { onRecord(entry, .taken) }
                            dismiss()
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
            .navigationTitle("\(line.slot.labelKo) \(line.time.description)")
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

    private func entryCard(_ entry: DayPlan.Entry) -> some View {
        JanjanCard(padding: CGFloat(JanjanSpacing.m)) {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    Text(entry.medicationName)
                        .janjanBody(16, weight: .medium)
                        .foregroundStyle(Color.ink)
                    PillChip(text: "\(DecimalQuantity.display(entry.dose))정")
                    Spacer(minLength: 0)
                    if let status = entry.status, status != .unrecorded {
                        PillChip(
                            text: status.labelKo,
                            tint: status == .taken ? .sage : .peach,
                            textTint: status == .taken ? .sageInk : .ink2
                        )
                    }
                }

                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    WhitePillButton(title: "복용함") { onRecord(entry, .taken) }
                    WhitePillButton(title: "건너뜀") { onRecord(entry, .skipped) }
                }
            }
        }
    }
}

#Preview {
    TodayView(isShowingSettings: .constant(false))
        .modelContainer(for: JanjanSchema.allModels, inMemory: true)
}
