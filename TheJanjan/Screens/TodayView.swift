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
    /// 되돌리기를 물어보는 중인 시간대.
    @State private var undoing: SlotSelection?
    /// 꽃가루를 내리는 중인지. 끝나면 스스로 꺼진다.
    @State private var isCelebrating = false
    /// 기본 접힘·펼침을 손으로 뒤집어 둔 시간대들.
    @State private var flippedSlots: Set<String> = []
    /// 마지막으로 축하한 날. 하루에 한 번만 내린다 - 되돌렸다가 다시
    /// 채울 때마다 터지면 축하가 아니라 방해가 된다.
    @AppStorage("janjan.today.celebratedDay") private var celebratedDay = ""
    @State private var safetyReason: SafetyReason?
    @State private var isShowingUnrecordedSheet = false
    @State private var isShowingNextVisitSheet = false
    #if DEBUG
    /// 화면 찍기 전용: `-JanjanShowUnrecorded` 인자가 있으면 뜨자마자 살펴보기
    /// 시트를 연다. simctl 로만 띄우는 영어 캡처가 버튼을 누를 수 없어서다.
    private let opensUnrecordedOnLaunch =
        ProcessInfo.processInfo.arguments.contains("-JanjanShowUnrecorded")
    #endif
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

    /// 자정을 넘기면 값이 바뀌어 화면이 다시 그려진다(JanjanClock).
    @ObservedObject private var clock = JanjanClock.shared
    private var today: Date { clock.today }
    private var lang: JanjanLanguage { .current }

    /// 약 이름 가리기가 실제로 적용되는지. Pro 가 아니면 켜져 있어도 아무 일도 하지 않는다.
    /// 약 이름을 가릴지.
    ///
    /// **Pro 여부를 보지 않는다**(QA 2026-09-19). 구독이 끝나는 순간 화면의
    /// 약 이름이 예고 없이 드러나면, 그것을 가리려고 켜 둔 사람에게는 최악의
    /// 실패다. 위젯과 알림은 애초에 구독을 물을 수 없어 저장된 값만 보고
    /// 가린 채로 남는데(안전한 실패), 화면만 반대로 동작하고 있었다.
    /// 테마도 같은 규칙이다 - 구독이 끝나도 이미 고른 색은 그대로 둔다.
    ///
    /// 켜는 일 자체는 여전히 Pro 에서만 할 수 있다(설정 화면의 자물쇠).
    private var masksNames: Bool { JanjanPrivacy.hidesNames }

    // MARK: - 저장소에서 읽어 온 것

    private var medications: [Medication] { medicationRecords.map { $0.core.displayReady } }
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
            // 오늘 것을 다 챙긴 순간 한 번. 스크롤 위가 아니라 화면 전체에
            // 얹어야 어디를 보고 있든 눈에 든다.
            .overlay { if isCelebrating { ConfettiBurst().id(celebratedDay) } }
            // 마지막 한 칸을 채우는 그 순간에만 터진다. 화면에 들어올 때마다
            // 다시 터지면 축하가 아니라 방해가 된다 - 그래서 날짜를 적어 둔다.
            .onChange(of: isTodayComplete) { _, complete in
                guard complete else { return }
                celebrate()
            }
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
            // 되돌리기는 한 번 묻는다. 복용 기록은 리포트의 분모와 재고를
            // 같이 움직이므로, 잘못 지우면 그 흔적이 진료실까지 간다.
            .confirmationDialog(
                t("정말 복약을 취소하시겠어요?", "Undo this dose record?"),
                isPresented: Binding(
                    get: { undoing != nil },
                    set: { if !$0 { undoing = nil } }
                ),
                titleVisibility: .visible,
                presenting: undoing
            ) { selection in
                Button(t("취소하기", "Undo"), role: .destructive) {
                    undoSlot(selection.id)
                    undoing = nil
                }
                Button(t("그대로 두기", "Keep it"), role: .cancel) { undoing = nil }
            } message: { _ in
                Text(t(
                    "이 시간대의 오늘 기록이 지워지고, 다시 답할 수 있게 돼요.",
                    "Today's entries for this slot are removed, and you can answer again."
                ))
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
            .sheet(isPresented: $isShowingNextVisitSheet) {
                NextVisitSheet()
            }
            #if DEBUG
            .onAppear {
                if opensUnrecordedOnLaunch && !unrecordedLines.isEmpty {
                    isShowingUnrecordedSheet = true
                }
            }
            #endif
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

    /// 오늘 챙길 것이 있었고, 그것을 다 챙겼는지.
    ///
    /// 예정이 아예 없는 날은 축하하지 않는다 - 아무것도 안 했는데 꽃가루가
    /// 내리면 이 앱이 무엇을 세고 있는지 알 수 없게 된다.
    private var isTodayComplete: Bool {
        !plan.isEmpty && DayPlan.pendingSlotCount(in: plan) == 0
    }

    /// 한 문장에 한 정보. 놓쳤다고 다그치지 않고 남은 것만 알린다.
    private var subtitleKo: String {
        guard hasAnyMedication else { return t("약을 등록하면 여기에 오늘 일정이 보여요.", "Add a medication and today's plan will show up here.") }
        let pending = DayPlan.pendingSlotCount(in: plan)
        if plan.isEmpty { return t("오늘은 예정된 약이 없어요.", "No medications are scheduled for today.") }
        if pending == 0 { return t("오늘 약은 다 챙기셨어요.", "You've taken all of today's meds.") }
        return t("오늘은 약을 \(pending)번 더 복용해야 해요.", "You have \(pending) more dose\(pending == 1 ? "" : "s") to take today.")
    }

    // MARK: - 시간대 타일

    /// 시간대 하나가 지금 어떤 처지인지.
    ///
    /// 화면에 시간대를 넷씩 전부 펼쳐 두면, 점심에 저녁 약까지 눌러 버리는
    /// 일이 생긴다(사용자 지적 2026-09-21). 지금 할 일만 펼쳐 둔다.
    enum SlotStanding {
        /// 다 적었다. 접는다 - 지나갔고 할 일이 없다.
        case done
        /// 시각이 지났는데 아직 답이 없다. 펼치고 표시를 단다.
        case overdue
        /// 다음 차례. 펼친다.
        case next
        /// 아직 멀었다. 접는다.
        case later

        var isExpandedByDefault: Bool {
            switch self {
            case .overdue, .next: return true
            case .done, .later: return false
            }
        }
    }

    /// 시간대마다의 처지. `plan` 은 시각 순이다.
    private var standings: [(line: DayPlan.SlotLine, standing: SlotStanding)] {
        let now = Date()
        var foundNext = false
        return plan.map { line in
            if line.isCompleted { return (line, .done) }
            if line.time.date(on: today) <= now { return (line, .overdue) }
            if !foundNext {
                foundNext = true
                return (line, .next)
            }
            return (line, .later)
        }
    }

    /// 접힘·펼침은 기본값을 따르되, 누르면 그 줄만 뒤집힌다.
    /// 뒤집은 것을 기억해 두므로 "저녁 약을 미리 보고 싶다" 도 된다.
    private func isExpanded(_ line: DayPlan.SlotLine, _ standing: SlotStanding) -> Bool {
        // 밀린 줄은 접지 못한다. 아까 손으로 접어 둔 것이 그대로 남아, 시각이
        // 지난 뒤에도 접혀 있으면 이 화면이 존재하는 이유가 사라진다.
        if standing == .overdue { return true }
        return standing.isExpandedByDefault != flippedSlots.contains(line.slotKey)
    }

    private var slotSection: some View {
        VStack(spacing: CGFloat(JanjanSpacing.s)) {
            ForEach(standings, id: \.line.id) { entry in
                if isExpanded(entry.line, entry.standing) {
                    slotTile(entry.line, standing: entry.standing)
                } else {
                    collapsedSlotRow(entry.line, standing: entry.standing)
                }
            }
        }
    }

    /// 접힌 시간대. 한 줄로 줄이되 **무엇이 남았는지는 그대로 말한다** -
    /// 접는 것은 실수를 줄이려는 것이지 숨기려는 것이 아니다.
    private func collapsedSlotRow(_ line: DayPlan.SlotLine, standing: SlotStanding) -> some View {
        Button {
            flip(line.slotKey)
        } label: {
            HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                Text(line.slot.label(lang))
                    .janjanBody(15, weight: .medium)
                    .foregroundStyle(Color.ink2)
                if !line.slot.isCustom {
                    Text(line.time.description)
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)
                }
                Spacer(minLength: CGFloat(JanjanSpacing.xs))
                if standing == .done {
                    Text(t("완료", "Done"))
                        .janjanBody(13)
                        .foregroundStyle(Color.janjan(.sageInk))
                } else {
                    Text(t("\(line.pendingCount)개 남음", "\(line.pendingCount) left"))
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.janjan(.line2))
            }
            .padding(.horizontal, CGFloat(JanjanSpacing.m))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.row), style: .continuous)
                    .fill(Color.janjan(.surface2))
            )
            .contentShape(RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.row), style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(t("눌러서 펼칩니다", "Tap to expand")))
    }

    private func flip(_ slotKey: String) {
        if flippedSlots.contains(slotKey) {
            flippedSlots.remove(slotKey)
        } else {
            flippedSlots.insert(slotKey)
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
    /// 오늘 몫을 다 채운 것을 한 번 축하한다.
    private func celebrate() {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: today)
        let key = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
        guard celebratedDay != key else { return }
        celebratedDay = key
        isCelebrating = true
        // 꽃가루가 다 내린 뒤에 걷는다. 켜 둔 채로 두면 화면이 다시 그려질
        // 때마다 조각이 처음 자리로 돌아가 깜빡인다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            isCelebrating = false
        }
    }

    /// 그 시간대의 오늘 기록을 통째로 지워 다시 물어볼 수 있게 한다.
    private func undoSlot(_ slotKey: String) {
        guard let line = plan.first(where: { $0.slotKey == slotKey }) else { return }
        for entry in line.entries {
            DoseRecorder.clear(
                medicationID: entry.medicationID,
                slotKey: slotKey,
                on: today,
                in: context
            )
        }
        save()
    }

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
    private func slotTile(_ line: DayPlan.SlotLine, standing: SlotStanding) -> some View {
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
                            // 시각이 지났는데 답이 없는 줄. 색만으로 말하지 않으려고
                            // 그림과 글자를 함께 둔다 - 저녁에 점심 약이 남아 있으면
                            // 두 줄이 나란히 서므로 어느 쪽이 밀린 것인지 보여야 한다.
                            if standing == .overdue {
                                HStack(spacing: 3) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(t("지난 시간대", "Overdue"))
                                        .janjanBody(11, weight: .semibold)
                                }
                                .foregroundStyle(Color.janjan(.peachInk))
                                .padding(.horizontal, CGFloat(JanjanSpacing.xs))
                                .padding(.vertical, 2)
                                .background(Capsule(style: .continuous).fill(Color.janjan(.peach)))
                                .fixedSize(horizontal: true, vertical: false)
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
                    //
                    // 다시 누르면 되돌린다. 잘못 눌러 놓고 시트를 열어 약마다
                    // 지우게 두면, 실수 하나를 무르는 데 손이 너무 많이 간다
                    // (사용자 요청 2026-09-21). 묻고 나서 지운다 - 되돌리기가
                    // 실수로 또 눌리면 처음 실수와 똑같은 일이 된다.
                    Button {
                        undoing = SlotSelection(id: line.slotKey)
                    } label: {
                        PillChip(text: t("완료", "Done"), tint: .surface, textTint: .sageInk)
                            .frame(minWidth: 96, minHeight: 56)
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(t(
                        "\(line.slot.labelKo) 약 완료됨",
                        "\(line.slot.label(.english)) doses done"
                    )))
                    .accessibilityHint(Text(t("눌러서 되돌립니다", "Tap to undo")))
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
    /// (시트 열기)과 겹친다. 그래서 `MaskedNameText` 대신 가려졌을 때는 블러만
    /// 보여 주고, 다시 눌러 보이게 하는 동작은 두지 않는다 - 시트를 열면 약마다
    /// `SlotRecordSheet` 의 `MaskedNameText` 로 따로 확인할 수 있다(약 목록 행과 같은 판단).
    private func slotNamesText(_ line: DayPlan.SlotLine) -> some View {
        Group {
            if masksNames {
                Text(line.medicationNames.joined(separator: " · "))
                    .blur(radius: MaskedNameText.blurRadius)
                    .clipped()
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
        // 흘려보내기 쉬운 줄이라 아이콘과 굵기, 테두리로 무게를 준다
        // (사용자 요청 2026-09-16: "좀 더 확실하게 꼭 기록할 수 있도록").
        JanjanCard {
            HStack(alignment: .center, spacing: CGFloat(JanjanSpacing.s)) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text(unrecordedSlotsMessage)
                    .janjanBody(14, weight: .semibold)
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                WhitePillButton(title: t("살펴보기", "Take a look")) {
                    isShowingUnrecordedSheet = true
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.card), style: .continuous)
                .strokeBorder(Color.janjan(.ink).opacity(0.25), lineWidth: 1.5)
        )
    }

    // MARK: - 필요시

    private var asNeededCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(t("비상약", "Rescue meds"))
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)
                Text(t(
                    "비상약을 드셨다면 눌러 주세요.",
                    "Tap when you take a rescue dose."
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
                     : t("오늘 기분을 기록해 보세요.", "Log how today felt."))
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
                    // 눌러서 다음 진료 일정을 바로 잡는다(사용자 요청 2026-09-19).
                    // 미정일 때만이 아니라 잡힌 날짜를 고칠 때도 같은 입구다.
                    Button {
                        isShowingNextVisitSheet = true
                    } label: {
                        PillChip(text: nextVisitText, tint: .surface2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text(t("다음 진료 일정을 정해요.", "Set the next visit date.")))
                    // 소진 예측은 Pro 다. 예전에는 무료에서 **아예 그리지
                    // 않았는데**, 그러면 잠긴 것이 아니라 없는 기능이 된다
                    // (사용자 지적 2026-09-21). 자물쇠를 얹어 보여 준다.
                    if let text = shortfallText {
                        if pro.isPro {
                            PillChip(text: text, tint: .surface2)
                        } else {
                            PillChip(text: text, tint: .surface2)
                                .blur(radius: 4)
                                .proGated(.runOutForecast)
                        }
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
        // 이름을 가려 둔 동안은 여기서도 부르지 않는다 - 개수로만 말한다.
        if short.count == 1 && !masksNames {
            return t("\(short[0].name) 모자람", "\(short[0].name) running low")
        }
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

/// 다음 진료 일정을 이 자리에서 잡는 시트 (사용자 요청 2026-09-19).
///
/// 처방 기록이 있으면 가장 최근 기록의 다음 진료일을 고치고, 하나도 없으면
/// 일정만 담은 기록을 만든다. 그 기록의 visitDate 를 미래(그 진료일)로 두는
/// 이유: 리포트의 "지난 진료" 앵커는 오늘 이전의 visitDate 만 보므로 오늘의
/// 리포트가 흔들리지 않고, 진료일이 지나면 자연히 마지막 진료가 된다.
private struct NextVisitSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \PrescriptionRecord.visitDate, order: .reverse)
    private var prescriptionRecords: [PrescriptionRecord]

    @State private var date = Date()
    @State private var didLoad = false

    /// 이미 잡혀 있는 가장 가까운 다음 진료.
    private var existing: Date? {
        prescriptionRecords
            .compactMap(\.nextVisitDate)
            .filter { $0 >= Calendar.current.startOfDay(for: Date()) }
            .min()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
                    JanjanCard(padding: CGFloat(JanjanSpacing.m)) {
                        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                            DatePicker(
                                t("다음 진료", "Next visit"),
                                selection: $date,
                                // 하한은 시각이 아니라 오늘 0시 - 오늘 이른 시각으로
                                // 잡힌 일정을 오후에 열어도 값이 범위 밖이 되지 않는다.
                                in: Calendar.current.startOfDay(for: Date())...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .janjanBody(15)
                            .tint(Color.ink)

                            Text(t(
                                "저장하면 진료 알림이 이 시각에 맞춰지고, 소진 예측도 이 날을 기준으로 계산돼요.",
                                "Saving sets the visit reminder to this time and anchors running-low forecasts to this date."
                            ))
                                .janjanBody(12)
                                .foregroundStyle(Color.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    BlackPillButton(title: t("저장", "Save")) { save() }

                    if existing != nil {
                        WhitePillButton(title: t("미정으로 되돌리기", "Clear the date")) { clear() }
                    }
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.top, CGFloat(JanjanSpacing.s))
                .padding(.bottom, CGFloat(JanjanSpacing.xxl))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle(t("다음 진료", "Next visit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                // 잡힌 날짜가 있으면 그걸 고치는 것부터. 없으면 2주 뒤 오전 10시 —
                // 어차피 고를 값이지만 자정보다 진료 시간에 가깝다.
                if let existing {
                    date = existing
                } else {
                    let calendar = Calendar.current
                    let base = calendar.date(byAdding: .day, value: 14, to: calendar.startOfDay(for: Date())) ?? Date()
                    date = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: base) ?? base
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// 약도 처방일수도 메모도 없는, 다음 진료 일정만 담은 기록인지.
    /// 이런 기록은 리포트의 "지난 진료" 로 세지 않고, 미정이 되면 지운다.
    private func isScheduleOnly(_ record: PrescriptionRecord) -> Bool {
        record.medicationIDValues.isEmpty && record.daysSupplied == 0 && record.clinicNote.isEmpty
    }

    private func save() {
        let now = Date()
        if let existing,
           let shown = prescriptionRecords.first(where: { $0.nextVisitDate == existing }) {
            // 화면에 보여 준 바로 그 날짜를 든 기록을 고친다 - 기록이 여럿일 때
            // 보이는 것과 저장이 어긋나면 안 된다(QA 2026-09-19).
            shown.nextVisitDate = date
            if isScheduleOnly(shown) { shown.visitDate = date }
        } else if let latest = prescriptionRecords.first(where: { $0.visitDate <= now }) {
            latest.nextVisitDate = date
            // 지난 일정만 담은 기록이 남아 있었으면 새 일정으로 되살린다 -
            // 지난 visitDate 를 그대로 두면 가짜 "지난 진료" 가 된다.
            if isScheduleOnly(latest) { latest.visitDate = date }
        } else {
            context.insert(PrescriptionRecord(
                visitDate: date,
                daysSupplied: 0,
                nextVisitDate: date,
                clinicNote: "",
                medicationIDValues: []
            ))
        }
        finish()
    }

    private func clear() {
        let todayStart = Calendar.current.startOfDay(for: Date())
        for record in prescriptionRecords {
            // 일정만 담은 기록은 날짜가 지났든 아니든 남길 이유가 없다 -
            // 남으면 지난 visitDate 가 가짜 "지난 진료" 가 된다(QA 2026-09-19).
            if isScheduleOnly(record) {
                context.delete(record)
            } else if (record.nextVisitDate ?? .distantPast) >= todayStart {
                record.nextVisitDate = nil
            }
        }
        finish()
    }

    private func finish() {
        try? context.save()
        Task { await ReminderPlanner.rescheduleAppointments(using: context) }
        dismiss()
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
    private var masksNames: Bool { JanjanPrivacy.hidesNames }

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
                        // 필요시 이력 줄(asNeededRow)과 같은 규칙 - 이름이 길면
                        // 두 줄로 꺾이며 칩 둘이 줄 사이에 뜬다. 한 줄로 자른다.
                        .lineLimit(1)
                    PillChip(text: t("\(DecimalQuantity.display(entry.dose))정", pillsEn(entry.dose)))
                    Spacer(minLength: 0)
                    if let status = entry.status, status != .unrecorded {
                        PillChip(
                            text: status.label(lang),
                            tint: status == .taken ? .sage : .peach,
                            textTint: status == .taken ? .sageInk : .ink2
                        )
                    }
                }

                // 흰 카드 위의 흰 알약은 보이지 않는다(QA 2026-09-19). 지나간
                // 시간대에 답하는 줄과 같은 면·같은 폭을 쓴다.
                AnswerPillRow(answers: [
                    .init(t("복용함", "Taken")) { onRecord(entry, .taken) },
                    .init(t("건너뜀", "Skipped")) { onRecord(entry, .skipped) }
                ])
            }
        }
    }
}

/// 기록 없이 지나간 시간대를 하나씩 물어보는 시트.
///
/// 어느 날 무슨 일이 있었는지는 사용자만 안다. 그래서 판단하지 않고 세 가지
/// 답만 내놓는다 - 먹었다, 건너뛰었다, 기억나지 않는다. 셋 다 똑같이 유효한 답이다.
///
/// 셋은 늘 한 줄에 나란히 있다. 그리고 한 시간대에 약이 여럿이면 그중 일부만
/// 먹었을 수도 있으므로, 약마다 따로 답하는 길을 한 겹 안에 둔다(2026-09-19).
private struct UnrecordedSlotsSheet: View {

    let lines: [UnrecordedSlots.Line]
    let language: JanjanLanguage
    let onAnswer: (UnrecordedSlots.Line, DayPlan.Entry, DoseEvent.Status) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var pro: ProStore

    /// 약마다 따로 답하려고 펼쳐 둔 줄. 답을 남겨 줄이 사라지면 자연히 잊힌다.
    @State private var splitLineIDs: Set<String> = []

    private var masksNames: Bool { JanjanPrivacy.hidesNames }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                    Text(t(
                        "어느 날을 어떻게 하셨는지는 본인만 알 수 있어요. 기억나는 대로 답해 주시고, 기억나지 않으면 그대로 적어 두면 됩니다. 여러 약 중 일부만 먹은 날은 약마다 따로 답할 수 있어요.",
                        "Only you can know what happened on each day. Answer what you remember — and if you don't remember, that's a fine answer too. If you took only some of the meds in a slot, you can answer each one separately."
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
        // 한 시간대에 약이 여럿이면 그중 일부만 먹었을 수도 있다. 흔한 쪽(전부
        // 같은 답)은 한 번에 끝내고, 나뉘는 쪽은 한 겹 안에 둔다 - 시간대 타일의
        // 두 손잡이와 같은 규칙이다.
        let hasMany = line.entries.count > 1
        let isSplit = hasMany && splitLineIDs.contains(line.id)

        return JanjanCard(padding: CGFloat(JanjanSpacing.m)) {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(UnrecordedSlots.title(for: line, language: language))
                    .janjanBody(16, weight: .medium)
                    .foregroundStyle(Color.ink)

                if isSplit {
                    ForEach(line.entries) { entry in
                        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                            // 오늘 시간대 시트와 같은 정보량을 준다 - 거기는
                            // 이름 옆에 늘 개수가 붙어 있다(QA 2026-09-19).
                            HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                                MaskedNameText(name: entry.medicationName, isMasked: masksNames)
                                    .janjanBody(14, weight: .medium)
                                    .foregroundStyle(Color.ink)
                                    .lineLimit(1)
                                PillChip(text: t(
                                    "\(DecimalQuantity.display(entry.dose))정",
                                    pillsEn(entry.dose)
                                ))
                                Spacer(minLength: 0)
                            }
                            answerRow(for: line, entries: [entry], allAtOnce: false)
                        }
                    }
                } else {
                    MaskedNameText(
                        name: line.entries.map(\.medicationName).joined(separator: " · "),
                        isMasked: masksNames
                    )
                        .janjanBody(13)
                        .foregroundStyle(Color.ink2)

                    answerRow(for: line, entries: line.entries, allAtOnce: hasMany)
                }

                if hasMany {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if isSplit {
                                splitLineIDs.remove(line.id)
                            } else {
                                splitLineIDs.insert(line.id)
                            }
                        }
                    } label: {
                        Text(isSplit
                             ? t("한꺼번에 답하기", "Answer all at once")
                             : t("약마다 따로 답하기", "Answer each medication"))
                            .janjanBody(13, weight: .medium)
                            .foregroundStyle(Color.ink2)
                            .underline()
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 세 답을 늘 한 줄로 그린다. `allAtOnce` 는 이 한 번이 그 시간대의 약
    /// 전부에 걸린다는 뜻이라, 문구에서도 "전부" 라고 말한다.
    private func answerRow(
        for line: UnrecordedSlots.Line,
        entries: [DayPlan.Entry],
        allAtOnce: Bool
    ) -> some View {
        AnswerPillRow(answers: [
            .init(allAtOnce ? t("전부 먹었어요", "All taken") : t("먹었어요", "Took it")) {
                for entry in entries { onAnswer(line, entry, .taken) }
            },
            .init(allAtOnce ? t("전부 건너뛰었어요", "All skipped") : t("건너뛰었어요", "Skipped it")) {
                for entry in entries { onAnswer(line, entry, .skipped) }
            },
            .init(t("기억나지 않아요", "I don't remember")) {
                for entry in entries { onAnswer(line, entry, .unrecorded) }
            }
        ])
    }
}


#Preview {
    TodayView(isShowingSettings: .constant(false))
        .modelContainer(for: JanjanSchema.allModels, inMemory: true)
}
