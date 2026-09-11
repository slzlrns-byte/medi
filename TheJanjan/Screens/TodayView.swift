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
    @State private var isShowingUnrecordedSheet = false
    /// 약별로 고른 필요시 개수. 고르지 않은 약은 `asNeededQuantity(for:)` 가
    /// 가장 최근 기록에서 기본값을 찾는다.
    @State private var asNeededQuantities: [UUID: Decimal] = [:]

    /// 개수 선택지. 0.25 단위까지 허용하는 저장 규칙과 달리 화면에서 고르는 값은
    /// 이 넷으로 좁힌다 - 필요시 약에서 실제로 쓰이는 값이 대체로 이 안에 있다.
    private let asNeededQuantityOptions: [Decimal] = [0.5, 1, 1.5, 2]

    /// 시트에 넘길 때 Identifiable 이 필요해 감싼다.
    private struct SafetyReason: Identifiable {
        let id = UUID()
        let reason: SafetyTrigger.Reason
    }

    /// 시트에는 값이 아니라 열쇠만 들고 간다. 값을 들고 가면 기록한 뒤에도
    /// 시트가 기록 전의 옛 줄을 계속 보여 준다.
    private struct SlotSelection: Identifiable { let id: String }

    private var today: Date { Date() }
    private var lang: JanjanLanguage { .current }

    /// 약 이름 가리기가 실제로 적용되는지. Pro 가 아니면 켜져 있어도 아무 일도 하지 않는다.
    private var masksNames: Bool { pro.isPro && JanjanPrivacy.hidesNames }

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
        // 같은 날 두 줄이 생긴 경우(동기화 충돌) 가장 나중에 손댄 값을 보여 준다.
        return checkInRecords
            .filter { calendar.isDate($0.date, inSameDayAs: today) }
            .max { $0.updatedAt < $1.updatedAt }?
            .moodScore
    }

    private var hasAnyMedication: Bool { !medicationRecords.isEmpty }

    /// 지금 복용 중인 필요시 약. 카드는 이게 하나라도 있을 때만 보인다.
    private var activeAsNeededMedications: [Medication] {
        medications.filter { $0.status == .active && $0.kind == .asNeeded }
    }

    /// 오늘 기록된 필요시 사건. 시각순으로 보여 준다.
    private var todaysAsNeededEvents: [DoseEventRecord] {
        let calendar = Calendar.current
        return doseRecords
            .filter {
                $0.kindRaw == DoseEvent.Kind.asNeeded.rawValue
                    && calendar.isDate($0.scheduledAt, inSameDayAs: today)
            }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    /// 오늘을 뺀 지난 7일에서 기록 없이 지나간 시간대.
    ///
    /// 오늘 지나간 시간대는 슬롯 타일에 이미 보이므로 여기서는 중복해 세지 않는다 -
    /// `until` 을 오늘 0시로 주면 어제까지만 찾는다.
    private var unrecordedLines: [UnrecordedSlots.Line] {
        let calendar = Calendar.current
        guard let from = calendar.date(byAdding: .day, value: -7, to: today) else { return [] }
        return UnrecordedSlots.find(
            from: from,
            until: calendar.startOfDay(for: today),
            schedules: schedules,
            medications: medications,
            doseEvents: doseEvents,
            calendar: calendar
        )
    }

    private var unrecordedSlotsMessage: String {
        let count = unrecordedLines.count
        let noun = count == 1 ? "slot" : "slots"
        return t(
            "기록 없이 지나간 시간대가 \(count)개 있어요.",
            "\(count) time \(noun) went by without a record."
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
                    hero
                    if !unrecordedLines.isEmpty {
                        unrecordedSlotsCard
                    }
                    if hasAnyMedication {
                        slotSection
                    } else {
                        emptyCard
                    }
                    if !activeAsNeededMedications.isEmpty {
                        asNeededCard
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
                    .accessibilityLabel(Text(t("설정", "Settings")))
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
            .sheet(isPresented: $isShowingUnrecordedSheet) {
                // 목록은 값이 아니라 매번 다시 계산해 넘긴다 - 답을 하나 남기면
                // 시트가 열려 있는 채로 그 줄이 목록에서 빠진다.
                UnrecordedSlotsSheet(lines: unrecordedLines, language: lang) { line, entry, status in
                    recordUnrecorded(entry, in: line, as: status)
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
        case 5..<11: return t("좋은 아침이에요", "Good morning")
        case 11..<17: return t("오후예요", "Good afternoon")
        case 17..<22: return t("저녁이에요", "Good evening")
        default: return t("늦은 시간이네요", "It's late")
        }
    }

    /// 한 문장에 한 정보. 놓쳤다고 다그치지 않고 남은 것만 알린다.
    private var subtitleKo: String {
        guard hasAnyMedication else { return t("약을 등록하면 여기에 오늘 일정이 보여요.", "Add a medication and today's plan will show up here.") }
        let pending = DayPlan.pendingSlotCount(in: plan)
        if plan.isEmpty { return t("오늘은 예정된 약이 없어요.", "No medications are scheduled for today.") }
        if pending == 0 { return t("오늘 약은 다 챙기셨어요.", "You've taken all of today's meds.") }
        return t("오늘 남은 시간대가 \(pending)번 있어요.", "\(pending) time \(pending == 1 ? "slot" : "slots") left today.")
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
                            Text(line.slot.label(lang))
                                .janjanDisplay(22)
                                .foregroundStyle(Color.ink)
                            // 직접 넣은 시간대는 이름이 곧 시각이라 두 번 말하지 않는다.
                            if !line.slot.isCustom {
                                Text(line.time.description)
                                    .janjanBody(13)
                                    .foregroundStyle(Color.ink2)
                            }
                        }
                        slotNamesText(line)
                            .janjanBody(14)
                            .foregroundStyle(Color.ink2)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(t("약마다 따로 기록합니다", "Record each medication separately")))

                if line.isCompleted {
                    // 색만으로 상태를 말하지 않는다. 글자가 항상 함께 온다.
                    // 높이는 아래 버튼과 맞춘다 - 다르면 다 적은 순간 타일이 튄다.
                    PillChip(text: t("완료", "Done"), tint: .surface, textTint: .sageInk)
                        .frame(minWidth: 96, minHeight: 56)
                } else {
                    Button {
                        recordRestTaken(in: line)
                    } label: {
                        VStack(spacing: 2) {
                            Text(t("먹었어요", "Took it"))
                                .janjanBody(15, weight: .medium)
                                .foregroundStyle(Color.ink)
                            Text(t("\(line.pendingCount)개", "\(line.pendingCount)"))
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
                    .accessibilityLabel(Text(t(
                        "\(line.slot.labelKo) 약 \(line.pendingCount)개 먹었어요",
                        "Took \(line.pendingCount) \(line.pendingCount == 1 ? "medication" : "medications") for \(line.slot.label(lang))"
                    )))
                    .accessibilityHint(Text(t("한 번에 기록합니다", "Records all of them at once")))
                }
            }
        }
    }

    /// 시간대 타일의 이름 줄.
    ///
    /// 이 타일 전체가 그 시간대를 여는 버튼이라, 이름 자리에 따로 탭을 두면 타일 탭
    /// (시트 열기)과 겹친다. 그래서 `MaskedNameText` 대신 가려졌을 때는 점 표기만
    /// 보여 주고, 다시 눌러 보이게 하는 동작은 두지 않는다 - 시트를 열면 약마다
    /// `SlotRecordSheet` 의 `MaskedNameText` 로 따로 확인할 수 있다(약 목록 행과 같은 판단).
    private func slotNamesText(_ line: DayPlan.SlotLine) -> some View {
        Group {
            if masksNames {
                Text(MaskedNameText.maskGlyph)
                    .accessibilityLabel(Text(t("가려진 약 이름", "Hidden medication name")))
            } else {
                Text(line.medicationNames.joined(separator: " · "))
            }
        }
    }

    private var emptyCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text(t("아직 등록한 약이 없어요", "No medications yet"))
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)
                Text(t("약 탭에서 하나만 추가해도 오늘 일정이 만들어져요.", "Add just one in the Meds tab, and today's plan appears."))
                    .janjanBody(13)
                    .foregroundStyle(Color.muted)
            }
        }
    }

    // MARK: - 기록 없이 지나간 시간대

    /// 재촉이 아니라 안내다 - 사실만 짧게 말하고 살펴볼지는 사용자가 고른다.
    private var unrecordedSlotsCard: some View {
        JanjanCard {
            HStack(alignment: .center, spacing: CGFloat(JanjanSpacing.s)) {
                Text(unrecordedSlotsMessage)
                    .janjanBody(14)
                    .foregroundStyle(Color.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                WhitePillButton(title: t("살펴보기", "Take a look")) {
                    isShowingUnrecordedSheet = true
                }
            }
        }
    }

    // MARK: - 필요시

    private var asNeededCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(t("필요시", "As needed"))
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)
                Text(t(
                    "드신 그 순간에 눌러 주세요. 몇 번이든 각각 기록됩니다.",
                    "Tap when you take it. Each time is recorded on its own."
                ))
                    .janjanBody(13)
                    .foregroundStyle(Color.muted)

                VStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    ForEach(activeAsNeededMedications) { medication in
                        asNeededRow(medication)
                    }
                }
                .padding(.top, CGFloat(JanjanSpacing.xxs))

                if !todaysAsNeededEvents.isEmpty {
                    VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                        ForEach(todaysAsNeededEvents) { event in
                            asNeededHistoryRow(event)
                        }
                    }
                    .padding(.top, CGFloat(JanjanSpacing.xs))
                }
            }
        }
    }

    private func asNeededRow(_ medication: Medication) -> some View {
        HStack(spacing: CGFloat(JanjanSpacing.xs)) {
            MaskedNameText(name: medication.displayTitle, isMasked: masksNames)
                .janjanBody(15, weight: .medium)
                .foregroundStyle(Color.ink)
                .lineLimit(1)

            Spacer(minLength: CGFloat(JanjanSpacing.xs))

            Menu {
                ForEach(asNeededQuantityOptions, id: \.self) { option in
                    Button {
                        asNeededQuantities[medication.id] = option
                    } label: {
                        Text(t("\(DecimalQuantity.display(option))정", pillsEn(option)))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(asNeededQuantityLabel(for: medication.id))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                }
                .janjanBody(13, weight: .medium)
                .foregroundStyle(Color.ink2)
                .padding(.horizontal, CGFloat(JanjanSpacing.s))
                .padding(.vertical, CGFloat(JanjanSpacing.xxs) + 2)
                .background(Capsule(style: .continuous).fill(Color.janjan(.surface2)))
            }

            WhitePillButton(title: t("먹었어요", "Took it")) {
                recordAsNeeded(medicationID: medication.id, quantity: asNeededQuantity(for: medication.id))
            }
        }
    }

    private func asNeededHistoryRow(_ event: DoseEventRecord) -> some View {
        HStack(spacing: CGFloat(JanjanSpacing.xs)) {
            // 시각·이름·개수가 한 문장이라, 가릴 때는 줄 전체를 하나로 가린다.
            MaskedNameText(name: asNeededHistoryText(event), isMasked: masksNames)
                .janjanBody(13)
                .foregroundStyle(Color.ink2)
            Spacer(minLength: 0)
            Button {
                deleteAsNeededEvent(event)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(t("이 기록 지우기", "Delete this entry")))
        }
    }

    private func asNeededHistoryText(_ event: DoseEventRecord) -> String {
        let time = asNeededTimeFormatter.string(from: event.scheduledAt)
        let name = medications.first(where: { $0.id == event.medicationID })?.displayTitle ?? ""
        let quantityText = t("\(DecimalQuantity.display(event.quantity))정", pillsEn(event.quantity))
        return "\(time) · \(name) \(quantityText)"
    }

    private var asNeededTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    /// 고른 값이 있으면 그것, 없으면 그 약의 가장 최근 필요시 기록의 개수, 그것도
    /// 없으면 1정.
    private func asNeededQuantity(for medicationID: UUID) -> Decimal {
        asNeededQuantities[medicationID] ?? defaultAsNeededQuantity(for: medicationID)
    }

    private func asNeededQuantityLabel(for medicationID: UUID) -> String {
        let quantity = asNeededQuantity(for: medicationID)
        return t("\(DecimalQuantity.display(quantity))정", pillsEn(quantity))
    }

    private func defaultAsNeededQuantity(for medicationID: UUID) -> Decimal {
        doseRecords
            .filter { $0.medicationID == medicationID && $0.kindRaw == DoseEvent.Kind.asNeeded.rawValue }
            .max { $0.scheduledAt < $1.scheduledAt }?
            .quantity ?? 1
    }

    // MARK: - 체크인

    private var checkInCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(t("오늘 기분", "Mood today"))
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)
                Text(todaysMoodScore == nil
                     ? t("하나만 골라도 괜찮아요. 나머지는 나중에 덧붙일 수 있어요.", "Choosing just one is fine. You can add the rest later.")
                     : t("언제든 다시 고를 수 있어요.", "You can change it any time."))
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
                Text(t("한눈에", "At a glance"))
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
        else { return t("다음 진료 미정", "Next visit not set") }
        return days == 0
            ? t("오늘 진료", "Visit today")
            : t("다음 진료 D-\(days)", "Next visit in \(days) days")
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

        guard !short.isEmpty else { return t("부족한 약 없음", "Nothing running low") }
        if short.count == 1 { return t("\(short[0].name) 모자람", "\(short[0].name) running low") }
        return t("모자라는 약 \(short.count)개", "\(short.count) meds running low")
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

    private func recordAsNeeded(medicationID: UUID, quantity: Decimal) {
        DoseRecorder.recordAsNeeded(
            medicationID: medicationID,
            quantity: quantity,
            source: .phone,
            in: context
        )
        save()
    }

    private func deleteAsNeededEvent(_ event: DoseEventRecord) {
        context.delete(event)
        save()
    }

    /// 지나간 시간대 시트의 세 답 중 하나를 그 줄의 약마다 남긴다.
    private func recordUnrecorded(
        _ entry: DayPlan.Entry,
        in line: UnrecordedSlots.Line,
        as status: DoseEvent.Status
    ) {
        DoseRecorder.record(
            medicationID: entry.medicationID,
            slotKey: line.slot.storageKey,
            status: status,
            source: .phone,
            on: line.day,
            at: line.plannedAt,
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
            Text(t("이 시간대가 지금은 없어요", "This time slot is gone"))
                .janjanDisplay(22)
                .foregroundStyle(Color.ink)
            Text(t("다른 기기에서 약이 바뀌었을 수 있어요.", "It may have changed on another device."))
                .janjanBody(14)
                .foregroundStyle(Color.muted)
            WhitePillButton(title: t("닫기", "Close")) { dismiss() }
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
    @EnvironmentObject private var pro: ProStore

    private var lang: JanjanLanguage { .current }
    private var masksNames: Bool { pro.isPro && JanjanPrivacy.hidesNames }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CGFloat(JanjanSpacing.s)) {
                    ForEach(line.entries) { entry in
                        entryCard(entry)
                    }

                    if line.entries.count > 1 {
                        WhitePillButton(title: t("모두 복용함", "Take all"), systemImage: "checkmark") {
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
            .navigationTitle(line.slot.isCustom ? line.time.description : "\(line.slot.label(lang)) \(line.time.description)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("닫기", "Close")) { dismiss() }
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
                    MaskedNameText(name: entry.medicationName, isMasked: masksNames)
                        .janjanBody(16, weight: .medium)
                        .foregroundStyle(Color.ink)
                    PillChip(text: t("\(DecimalQuantity.display(entry.dose))정", "\(DecimalQuantity.display(entry.dose)) pills"))
                    Spacer(minLength: 0)
                    if let status = entry.status, status != .unrecorded {
                        PillChip(
                            text: status.label(lang),
                            tint: status == .taken ? .sage : .peach,
                            textTint: status == .taken ? .sageInk : .ink2
                        )
                    }
                }

                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    WhitePillButton(title: t("복용함", "Taken")) { onRecord(entry, .taken) }
                    WhitePillButton(title: t("건너뜀", "Skipped")) { onRecord(entry, .skipped) }
                }
            }
        }
    }
}

/// 기록 없이 지나간 시간대를 하나씩 물어보는 시트.
///
/// 어느 날 무슨 일이 있었는지는 사용자만 안다. 그래서 판단하지 않고 세 가지
/// 답만 내놓는다 - 먹었다, 건너뛰었다, 기억나지 않는다. 셋 다 똑같이 유효한 답이다.
private struct UnrecordedSlotsSheet: View {

    let lines: [UnrecordedSlots.Line]
    let language: JanjanLanguage
    let onAnswer: (UnrecordedSlots.Line, DayPlan.Entry, DoseEvent.Status) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pro: ProStore

    private var masksNames: Bool { pro.isPro && JanjanPrivacy.hidesNames }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                    Text(t(
                        "어느 날을 어떻게 하셨는지는 본인만 알 수 있어요. 기억나는 대로 답해 주시고, 기억나지 않으면 그대로 적어 두면 됩니다.",
                        "Only you can know what happened on each day. Answer what you remember — and if you don't remember, that's a fine answer too."
                    ))
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)

                    if lines.isEmpty {
                        Text(t("모두 답했어요.", "All answered."))
                            .janjanBody(15, weight: .medium)
                            .foregroundStyle(Color.ink)
                            .padding(.top, CGFloat(JanjanSpacing.l))
                    } else {
                        ForEach(lines) { line in
                            lineCard(line)
                        }
                    }
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.top, CGFloat(JanjanSpacing.s))
                .padding(.bottom, CGFloat(JanjanSpacing.xxl))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle(t("기록 없이 지나간 시간대", "Unrecorded time slots"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func lineCard(_ line: UnrecordedSlots.Line) -> some View {
        JanjanCard(padding: CGFloat(JanjanSpacing.m)) {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(UnrecordedSlots.title(for: line, language: language))
                    .janjanBody(16, weight: .medium)
                    .foregroundStyle(Color.ink)
                MaskedNameText(
                    name: line.entries.map(\.medicationName).joined(separator: " · "),
                    isMasked: masksNames
                )
                    .janjanBody(13)
                    .foregroundStyle(Color.ink2)

                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    WhitePillButton(title: t("먹었어요", "Took it")) {
                        for entry in line.entries { onAnswer(line, entry, .taken) }
                    }
                    WhitePillButton(title: t("건너뛰었어요", "Skipped it")) {
                        for entry in line.entries { onAnswer(line, entry, .skipped) }
                    }
                }
                WhitePillButton(title: t("기억나지 않아요", "I don't remember")) {
                    for entry in line.entries { onAnswer(line, entry, .unrecorded) }
                }
            }
        }
    }
}

#Preview {
    TodayView(isShowingSettings: .constant(false))
        .modelContainer(for: JanjanSchema.allModels, inMemory: true)
}
