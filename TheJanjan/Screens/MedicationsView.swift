import SwiftUI
import SwiftData
import JanjanCore

/// 약 — 처방·재고 관리 (설계 03절).
///
/// 한 줄에 이름·용량 알약칩·용도 한 줄·잔여 개수. 잔여는 저장된 값이 아니라
/// InventoryCalculator 가 사건에서 매번 다시 계산한 값이다.
struct MedicationsView: View {

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var pro: ProStore

    @Query(sort: \MedicationRecord.createdAt) private var medicationRecords: [MedicationRecord]
    @Query private var scheduleRecords: [ScheduleRecord]
    @Query private var doseRecords: [DoseEventRecord]
    @Query private var stockRecords: [StockEventRecord]
    @Query(sort: \PrescriptionRecord.visitDate, order: .reverse)
    private var prescriptionRecords: [PrescriptionRecord]

    @State private var isShowingAddFlow = false
    @State private var isShowingPrescription = false
    @State private var isShowingVisitHistory = false
    @State private var pendingDeletion: Row?

    private var today: Date { Date() }
    private var lang: JanjanLanguage { .current }

    /// 약 이름 가리기가 실제로 적용되는지. Pro 가 아니면 켜져 있어도 아무 일도 하지 않는다.
    private var masksNames: Bool { pro.isPro && JanjanPrivacy.hidesNames }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: CGFloat(JanjanSpacing.s)) {
                    prescriptionCard
                    if sections.isEmpty {
                        emptyCard
                    }
                    ForEach(sections, id: \.title) { section in
                        sectionHeader(section.title)
                        ForEach(section.rows) { row in
                            NavigationLink {
                                MedicationDetailView(medicationID: row.id)
                            } label: {
                                medicationRow(row)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("medicationRow")
                        }
                    }
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle(t("약", "Meds"))
            .navigationBarTitleDisplayMode(.large)
            // 약을 더하는 손잡이는 제목 줄에 둔다. 오늘 화면의 설정 버튼과 같은 자리다.
            //
            // 원래는 떠 있는 검은 원 버튼이었는데 두 번 고치고도 계속 목록을 가렸다.
            // 처음에는 아래 여백으로, 다음에는 safeAreaInset 으로 막으려 했다.
            // 둘 다 틀렸다 - safeAreaInset 은 '마지막 줄까지 스크롤로 닿게' 해 줄 뿐,
            // 목록 중간에서 버튼 밑으로 내용이 지나가는 것은 그대로다. 사진에서
            // '로라제팜 10정' 의 개수가 세 번째로 가려진 것을 보고 접었다.
            //
            // 떠 있는 버튼은 구조상 늘 무언가를 덮는다. 그리고 약을 더하는 일은
            // 자주 하는 일이 아니다 - 처음에 몇 번 하고 나면 거의 안 한다.
            // 화면에서 가장 큰 손잡이를 줄 만한 동작이 아니었다.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAddFlow = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.ink2)
                    }
                    .accessibilityLabel(Text(t("약 추가", "Add medication")))
                }
            }
            .sheet(isPresented: $isShowingAddFlow) {
                AddMedicationEntryView()
            }
            #if DEBUG
            // 화면 찍기 전용: simctl 로만 띄우는 캡처는 탭을 못 누르므로
            // -JanjanShowPillFinder 로 약 추가 시트를 바로 연다.
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-JanjanShowPillFinder") {
                    isShowingAddFlow = true
                }
            }
            #endif
            .sheet(isPresented: $isShowingPrescription) {
                NavigationStack {
                    PrescriptionFormView { isShowingPrescription = false }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(t("닫기", "Close")) { isShowingPrescription = false }
                                    .foregroundStyle(Color.ink)
                            }
                        }
                }
            }
            .sheet(isPresented: $isShowingVisitHistory) {
                VisitHistoryView()
            }
            .confirmationDialog(
                t("이 약의 기록을 모두 지울까요?", "Delete all records for this medication?"),
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    // 바깥을 눌러 닫았을 때도 고른 줄을 놓아 준다.
                    // .constant 로 두면 한 번 닫힌 뒤 다시는 열리지 않는다.
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { row in
                Button(t("삭제", "Delete"), role: .destructive) { delete(row) }
                Button(t("취소", "Cancel"), role: .cancel) { pendingDeletion = nil }
            } message: { row in
                // 목록에서 가려 둔 이름이 확인 창에서 새면 안 된다 - 가린 동안은 부르지 않는다.
                if masksNames {
                    Text(t(
                        "복용 기록과 재고 기록이 함께 사라져요. 되돌릴 수 없어요.",
                        "This removes its dose and stock records together. This can't be undone."
                    ))
                } else {
                    Text(t(
                        "\(row.medication.name) 의 복용 기록과 재고 기록이 함께 사라져요. 되돌릴 수 없어요.",
                        "This removes \(row.medication.name)'s dose and stock records together. This can't be undone."
                    ))
                }
            }
        }
    }

    // MARK: - 데이터

    struct Row: Identifiable {
        let id: UUID
        let medication: Medication
        let snapshot: InventoryCalculator.Snapshot
        /// 재고를 한 번도 세지 않았으면 잔여를 숫자로 말하지 않는다.
        let hasStock: Bool
        /// 마지막 재고 사건 이후의 총량·소비량. "17/28정 · 총 9정 복용" 의 재료.
        let cycle: InventoryCalculator.CycleStatus?
    }

    private struct RowGroup {
        let title: String
        let rows: [Row]
    }

    private var medications: [Medication] { medicationRecords.map { $0.core.displayReady } }
    private var schedules: [Schedule] { scheduleRecords.map(\.core) }
    private var doseEvents: [DoseEvent] { doseRecords.map(\.core) }
    private var stockEvents: [StockEvent] { stockRecords.map(\.core) }

    /// 가장 가까운 다음 진료. 부족 판단의 기준선이다.
    private var nextVisit: Date? {
        prescriptionRecords
            .compactMap { $0.core.nextVisitDate }
            .filter { $0 >= today }
            .min()
    }

    private var rows: [Row] {
        let stock = stockEvents
        let doses = doseEvents
        let visit = nextVisit

        return medications.map { medication in
            Row(
                id: medication.id,
                medication: medication,
                snapshot: InventoryCalculator.snapshot(
                    medicationID: medication.id,
                    schedules: schedules,
                    stockEvents: stock,
                    doseEvents: doses,
                    nextVisit: visit,
                    asOf: today
                ),
                hasStock: stock.contains { $0.medicationID == medication.id },
                cycle: InventoryCalculator.cycleStatus(
                    for: medication.id,
                    stockEvents: stock,
                    doseEvents: doses,
                    asOf: today
                )
            )
        }
    }

    private var sections: [RowGroup] {
        let all = rows
        return [
            RowGroup(title: t("복용 중", "Taking"), rows: all.filter {
                $0.medication.status == .active && $0.medication.kind == .scheduled
            }),
            RowGroup(title: t("비상약", "Rescue meds"), rows: all.filter {
                $0.medication.status == .active && $0.medication.kind == .asNeeded
            }),
            RowGroup(title: t("중단", "Stopped"), rows: all.filter { $0.medication.status == .stopped })
        ]
        .filter { !$0.rows.isEmpty }
    }

    // MARK: - 조각

    /// 다음 진료와 처방 기록 입구.
    ///
    /// 검은 원 버튼은 화면당 하나(약 추가)라서 여기서는 흰 알약을 쓴다(설계 02절).
    /// 다음 진료까지 못 버티는 복용 중 약의 개수. 진료일이 없으면 nil(계산 불가).
    private var shortageCount: Int? {
        guard nextVisit != nil else { return nil }
        let count = rows.filter {
            $0.medication.status == .active && ($0.snapshot.shortfallDays ?? 0) > 0
        }.count
        return count
    }

    private var prescriptionCard: some View {
        JanjanCard(padding: CGFloat(JanjanSpacing.m)) {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    Text(nextVisitText)
                        .janjanBody(15, weight: .medium)
                        .foregroundStyle(Color.ink)
                    Spacer(minLength: 0)
                }

                // 모자라는 약이 있으면 이 카드가 먼저 말한다(사용자 요청 2026-09-16).
                // 색만으로 구분하지 않는다 - 아이콘과 문장이 같은 말을 한다.
                if let shortage = shortageCount, shortage > 0 {
                    HStack(alignment: .top, spacing: CGFloat(JanjanSpacing.xxs)) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.ink)
                        Text(t(
                            "다음 진료 전에 모자라는 약이 \(shortage)개 있어요. 아래 약 줄에서 확인해 주세요.",
                            "\(shortage) medication\(shortage == 1 ? "" : "s") will run short before the next visit. Check the rows below."
                        ))
                        .janjanBody(12, weight: .semibold)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(nextVisit == nil
                         ? t("진료일과 받아 온 개수를 적어 두면 소진 예측이 켜져요.", "Add a visit date and how many pills you picked up, and running-low forecasts turn on.")
                         : t("다음 진료 전에 모자라는 약이 없어요.", "No medication runs short before the next visit."))
                        .janjanBody(12)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // HStack 이 아니라 FlowRow: 큰 글씨 설정에서 두 캡슐이 카드 폭을
                // 넘으면 잘리는 대신 줄을 바꾼다(QA 2026-09-19).
                FlowRow(spacing: CGFloat(JanjanSpacing.xs)) {
                    WhitePillButton(title: t("처방 기록하기", "Log a prescription"), systemImage: "doc.text") {
                        isShowingPrescription = true
                    }
                    .overlay(
                        Capsule(style: .continuous).strokeBorder(Color.hairline, lineWidth: 1)
                    )

                    // 남긴 진료가 있어야 여는 문을 보여 준다 - 빈 화면으로 이끌지 않는다.
                    if hasVisitHistory {
                        WhitePillButton(title: t("지난 진료", "Past visits"), systemImage: "clock") {
                            isShowingVisitHistory = true
                        }
                        .overlay(
                            Capsule(style: .continuous).strokeBorder(Color.hairline, lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding(.top, CGFloat(JanjanSpacing.s))
    }

    /// 실제로 다녀온 진료가 하나라도 있는지. VisitHistoryView 와 같은 규칙으로 센다.
    private var hasVisitHistory: Bool {
        prescriptionRecords.contains {
            !($0.medicationIDValues.isEmpty && $0.daysSupplied == 0 && $0.clinicNote.isEmpty)
                && $0.visitDate <= today
        }
    }

    private var nextVisitText: String {
        guard let nextVisit else { return t("다음 진료 미정", "Next visit not set") }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: today),
            to: Calendar.current.startOfDay(for: nextVisit)
        ).day ?? 0
        return days == 0
            ? t("오늘 진료", "Visit today")
            : t("다음 진료 D-\(days)", "Next visit in \(days) days")
    }

    private var emptyCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text(t("첫 약을 등록해 볼까요", "Let's add your first medication"))
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)
                Text(t("이름과 시간만으로 시작할 수 있어요.", "A name and a time is all it takes to start."))
                    .janjanBody(13)
                    .foregroundStyle(Color.muted)

                // 손이 문구 바로 아래로 가게 등록 입구를 카드 안에 둔다
                // (사용자 요청 2026-09-19 - 이전 문구는 "오른쪽 아래 +" 라고
                // 안내했는데 실제 + 는 오른쪽 위에 있었다).
                WhitePillButton(title: t("약 등록하기", "Add a medication"), systemImage: "plus") {
                    isShowingAddFlow = true
                }
                .overlay(
                    Capsule(style: .continuous).strokeBorder(Color.hairline, lineWidth: 1)
                )
                .padding(.top, CGFloat(JanjanSpacing.xxs))
            }
        }
        .padding(.top, CGFloat(JanjanSpacing.s))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .janjanBody(13, weight: .medium)
            .foregroundStyle(Color.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, CGFloat(JanjanSpacing.s))
            .padding(.horizontal, CGFloat(JanjanSpacing.xxs))
    }

    /// 목록 행 안의 약 이름.
    ///
    /// 이 줄은 `MaskedNameText` 를 그대로 쓰지 않는다 — 행 전체가 `NavigationLink` 라
    /// 이름 자리에 따로 탭 손짓을 얹으면 행 탭(상세로 이동)과 겹친다. 그래서 여기서는
    /// 가려졌을 때 점 표기만 보이고, 다시 누르면 보이는 동작은 두지 않는다. 이름을
    /// 보려면 상세로 들어가면 된다 - 거기서는 `MaskedNameText` 가 제대로 동작한다.
    private func medicationNameText(_ medication: Medication) -> some View {
        Group {
            if masksNames {
                // 이름 자체를 블러로 가린다(사용자 결정 2026-09-16). 글자로 보려면
                // 상세로 들어간다 - 거기서 MaskedNameText 를 누르면 보인다.
                Text(medication.name)
                    .blur(radius: MaskedNameText.blurRadius)
                    .clipped()
                    .accessibilityLabel(Text(t("가려진 약 이름", "Hidden medication name")))
            } else {
                Text(medication.name)
            }
        }
    }

    private func medicationRow(_ row: Row) -> some View {
        JanjanCard(padding: CGFloat(JanjanSpacing.m)) {
            HStack(alignment: .top, spacing: CGFloat(JanjanSpacing.s)) {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                    HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                        medicationNameText(row.medication)
                            .janjanBody(16, weight: .medium)
                            .foregroundStyle(Color.ink)
                            // 이름이 두 줄이 되면 옆 칩이 줄 사이에 뜬다.
                            // 목록에서는 한 줄로 자르고, 전체 이름은 상세에서 본다.
                            .lineLimit(1)
                        if !row.medication.strengthText.isEmpty {
                            PillChip(text: row.medication.strengthText)
                        }
                    }
                    if !row.medication.purposeLine.isEmpty {
                        Text(row.medication.purposeLine)
                            .janjanBody(13)
                            .foregroundStyle(Color.muted)
                    }
                }

                Spacer(minLength: CGFloat(JanjanSpacing.xs))

                VStack(alignment: .trailing, spacing: 2) {
                    if row.hasStock {
                        // "17/28정" - 남은 숫자만으로는 많은지 적은지 모른다.
                        // 이번 구간의 총량이 눈금이 된다(사용자 결정 2026-09-16).
                        // 남은 개수는 굵고 크게, 총량은 얇고 작게 - 눈이 먼저 잡을 것은
                        // 지금 남은 쪽이다(사용자 요청 2026-09-16).
                        let remaining = max(row.snapshot.remaining, 0)
                        if let cycle = row.cycle, cycle.total > 0 {
                            (
                                Text(DecimalQuantity.display(remaining))
                                    .font(JanjanFont.displayStrong(20).monospacedDigit())
                                    .foregroundColor(Color.ink)
                                + Text(t("/\(DecimalQuantity.display(cycle.total))정", "/\(DecimalQuantity.display(cycle.total)) pills"))
                                    .font(JanjanFont.display(15).monospacedDigit())
                                    .foregroundColor(Color.muted)
                            )
                        } else {
                            Text(t("\(DecimalQuantity.display(remaining))정", pillsEn(remaining)))
                                .janjanDisplay(20)
                                .foregroundStyle(Color.ink)
                                .monospacedDigit()
                        }
                        if let cycle = row.cycle, cycle.consumed > 0 {
                            Text(t("총 \(DecimalQuantity.display(cycle.consumed))정 복용", "\(DecimalQuantity.display(cycle.consumed)) taken so far"))
                                .janjanBody(12)
                                .foregroundStyle(Color.muted)
                                .monospacedDigit()
                        }
                    } else {
                        Text(t("재고 미기록", "No count yet"))
                            .janjanBody(13)
                            .foregroundStyle(Color.muted)
                    }
                    if let text = runOutText(row) {
                        Text(text)
                            .janjanBody(12)
                            .foregroundStyle(Color.muted)
                    }
                }
            }
        }
        .contextMenu {
            if row.medication.status == .active {
                Button(t("복용 중단", "Stop taking")) {
                    MedicationStore.setStatus(.stopped, for: row.id, in: context)
                    rescheduleReminders()
                }
            } else {
                Button(t("다시 복용", "Resume")) {
                    MedicationStore.setStatus(.active, for: row.id, in: context)
                    rescheduleReminders()
                }
            }
            Button(t("삭제", "Delete"), role: .destructive) { pendingDeletion = row }
        }
    }

    /// 잔여 개수는 무료다 — 사용자가 직접 센 숫자이므로.
    /// **앞으로 며칠 남는지 내다보는 것만 Pro** 다(ASC 구독 설명이 약속한 네 가지 중 하나).
    private func runOutText(_ row: Row) -> String? {
        guard row.hasStock else { return nil }

        // 세어 둔 것보다 많이 먹은 것으로 계산되면 음수가 나온다.
        // 0 으로 깎아 보이되 그 사실을 숨기지는 않는다 — 다시 세어 달라고 말한다.
        if row.snapshot.remaining < 0 { return t("다시 세어 주세요", "Please recount") }
        guard pro.isPro else { return nil }

        if let shortfall = row.snapshot.shortfallDays, shortfall > 0 {
            return t("진료 전 \(shortfall)일 모자람", "\(shortfall) days short before the visit")
        }
        guard let days = row.snapshot.daysRemaining else { return nil }
        return t("약 \(DecimalQuantity.floorToInt(days))일치", "About \(DecimalQuantity.floorToInt(days)) days' worth")
    }

    // MARK: - 손대기

    private func delete(_ row: Row) {
        MedicationStore.delete(medicationID: row.id, in: context)
        pendingDeletion = nil
        rescheduleReminders()
    }

    private func rescheduleReminders() {
        Task { await ReminderPlanner.reschedule(using: context) }
    }
}

/// 약 추가의 첫 갈림길. 직접 입력은 무료, 약봉투 스캔은 Pro다(유도 세 곳 중 하나).
private struct AddMedicationEntryView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingForm = false
    @State private var isShowingScan = false
    @State private var isShowingPillFinder = false

    var body: some View {
        NavigationStack {
            VStack(spacing: CGFloat(JanjanSpacing.s)) {
                entryRow(
                    title: t("직접 입력", "Enter manually"),
                    subtitle: t("이름 · 용량 · 시간을 하나씩 적어요.", "Enter the name, dose, and time one by one."),
                    systemImage: "square.and.pencil"
                ) {
                    isShowingForm = true
                }
                // 카드 안에 글자가 두 줄이라 이름만으로는 UI 테스트가 못 찾는다.
                .accessibilityIdentifier("directEntry")

                entryRow(
                    title: ProFeature.pharmacyScan.title(.current),
                    subtitle: t("봉투 사진에서 약 이름을 읽어 와요. 사진은 저장되지 않아요.", "Reads medication names from a photo of the bag. The photo isn't saved."),
                    systemImage: "camera"
                ) {
                    isShowingScan = true
                }
                .proGated(.pharmacyScan)

                entryRow(
                    title: ProFeature.pillFinder.title(.current),
                    subtitle: t("모양·색·각인으로 어떤 약인지 좁혀 봐요.", "Narrow it down by shape, color, and imprint."),
                    systemImage: "circle.grid.2x2"
                ) {
                    isShowingPillFinder = true
                }
                .proGated(.pillFinder)

                Spacer()
            }
            .padding(.horizontal, CGFloat(JanjanSpacing.m))
            .padding(.top, CGFloat(JanjanSpacing.m))
            .fogBackground()
            .navigationTitle(t("약 추가", "Add medication"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
            .navigationDestination(isPresented: $isShowingForm) {
                MedicationFormView { dismiss() }
            }
            .navigationDestination(isPresented: $isShowingScan) {
                PharmacyScanView { dismiss() }
            }
            .navigationDestination(isPresented: $isShowingPillFinder) {
                PillFinderView { dismiss() }
            }
            #if DEBUG
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-JanjanShowPillFinder") {
                    isShowingPillFinder = true
                }
            }
            #endif
        }
    }

    private func entryRow(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            JanjanCard(padding: CGFloat(JanjanSpacing.m)) {
                HStack(spacing: CGFloat(JanjanSpacing.s)) {
                    CircleGlyph(systemImage: systemImage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .janjanBody(16, weight: .medium)
                            .foregroundStyle(Color.ink)
                        Text(subtitle)
                            .janjanBody(12)
                            .foregroundStyle(Color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: CGFloat(JanjanSpacing.xs))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MedicationsView()
        .modelContainer(for: JanjanSchema.allModels, inMemory: true)
        .environmentObject(ProStore())
}
