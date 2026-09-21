import SwiftUI
import SwiftData
import JanjanCore

/// 약 하나의 상세 (설계 03절).
///
/// 여기 있는 "선생님이 말씀하신 것" 이 식약처 이상반응 원문을 대신한다(2026-08-26 결정).
/// 앱이 바깥에서 목록을 들여와 펼쳐 보이지 않고, 담당의가 이미 골라 준 몇 줄을 붙들어 둔다.
struct MedicationDetailView: View {

    let medicationID: UUID

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var pro: ProStore

    @Query private var medicationRecords: [MedicationRecord]
    @Query private var scheduleRecords: [ScheduleRecord]
    @Query private var doseRecords: [DoseEventRecord]
    @Query private var stockRecords: [StockEventRecord]
    @Query private var symptomRecords: [SymptomEntryRecord]
    @Query private var doseChangeRecords: [DoseChangeRecord]
    @Query(sort: \MedicationNoteRecord.createdAt) private var noteRecords: [MedicationNoteRecord]
    @Query(sort: \PrescriptionRecord.visitDate, order: .reverse)
    private var prescriptionRecords: [PrescriptionRecord]

    @State private var composing: MedicationNote.Kind?
    @State private var isShowingDoseChangeSheet = false
    @State private var pendingDoseChangeDeletion: DoseChangeRecord?
    @State private var pendingNoteDeletion: MedicationNoteRecord?
    @State private var selectedAsNeededQuantity: Decimal?
    @State private var isShowingRecountSheet = false
    @State private var comparingChange: DoseChangeRecord?

    /// 자정을 넘기면 값이 바뀌어 화면이 다시 그려진다(JanjanClock).
    @ObservedObject private var clock = JanjanClock.shared
    private var today: Date { clock.today }
    private var lang: JanjanLanguage { .current }

    /// 약 이름 가리기가 실제로 적용되는지. Pro 가 아니면 켜져 있어도 아무 일도 하지 않는다.
    private var masksNames: Bool { JanjanPrivacy.hidesNames }

    private var record: MedicationRecord? {
        medicationRecords.first { $0.id == medicationID }
    }

    private var medication: Medication? { record?.core.displayReady }

    private var myNotes: [MedicationNoteRecord] {
        noteRecords.filter { $0.medicationID == medicationID }
    }

    /// 이 약의 시간대. 고치기 화면이 지금 값을 그대로 들고 열리게 한다.
    private var mySchedules: [Schedule] {
        scheduleRecords
            .filter { $0.medicationID == medicationID }
            .map(\.core)
            .sorted { $0.timeOfDay < $1.timeOfDay }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: CGFloat(JanjanSpacing.s)) {
                if let medication {
                    headerCard(medication)
                    stockCard(medication)
                    // 중단한 약은 "지금 먹었어요" 를 내밀지 않는다 - 오늘 화면과 같은 규칙.
                    if medication.kind == .asNeeded && medication.status == .active {
                        asNeededCard(medication)
                    }
                    doseChangeCard
                    scheduleCard
                    noteCard(.heardFromDoctor)
                    noteCard(.questionForDoctor)
                    statusCard(medication)
                } else {
                    // 다른 화면에서 지운 뒤 이 화면이 남아 있는 경우.
                    JanjanCard {
                        Text(t("이 약은 지워졌어요.", "This medication has been deleted."))
                            .janjanBody(15)
                            .foregroundStyle(Color.muted)
                    }
                }

                MedicalDisclaimer()
                    .padding(.horizontal, CGFloat(JanjanSpacing.xxs))
                    .padding(.top, CGFloat(JanjanSpacing.s))
            }
            .padding(.horizontal, CGFloat(JanjanSpacing.m))
            .padding(.top, CGFloat(JanjanSpacing.s))
            .padding(.bottom, CGFloat(JanjanSpacing.xxl))
        }
        .fogBackground()
        .scrollContentBackground(.hidden)
        .navigationTitle(masksNames ? t("약", "Medication") : (medication?.name ?? t("약", "Medication")))
        .navigationBarTitleDisplayMode(.inline)
        // 등록한 뒤에는 이름도 1회 개수도 먹는 때도 고칠 길이 없었다
        // (사용자 발견 2026-09-19). 상세 화면이 그 약에 대해 할 수 있는 일이
        // 모이는 자리이므로 손잡이도 여기 제목 줄에 둔다.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let medication {
                    NavigationLink {
                        MedicationFormView(existing: MedicationFormView.Existing(
                            medication: medication,
                            schedules: mySchedules
                        ))
                    } label: {
                        Text(t("고치기", "Edit"))
                            .foregroundStyle(Color.ink)
                    }
                }
            }
        }
        .sheet(item: $composing) { kind in
            MedicationNoteComposer(kind: kind) { text, symptomID in
                addNote(kind: kind, text: text, symptomID: symptomID)
            }
        }
        .sheet(isPresented: $isShowingDoseChangeSheet) {
            if let medication {
                DoseChangeSheet(previousText: medication.strengthText) { changedAt, fromText, toText, note in
                    saveDoseChange(changedAt: changedAt, fromText: fromText, toText: toText, note: note)
                }
            }
        }
        .sheet(isPresented: $isShowingRecountSheet) {
            StockRecountSheet(medicationID: medicationID)
        }
        #if DEBUG
        // 화면 찍기 전용: simctl 로 띄우는 영어 캡처는 눌러 들어갈 수 없다.
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-JanjanShowRecount") {
                isShowingRecountSheet = true
            }
            guard ProcessInfo.processInfo.arguments.contains("-JanjanShowDoseCompare"),
                  comparingChange == nil,
                  let first = doseChangeRecords
                      .filter({ $0.medicationID == medicationID })
                      .sorted(by: { $0.changedAt > $1.changedAt })
                      .first
            else { return }
            comparingChange = first
        }
        #endif
        .sheet(item: $comparingChange) { entry in
            DoseChangeCompareSheet(
                change: entry.core,
                medicationName: medication?.name ?? "",
                masksNames: masksNames
            )
        }
        .confirmationDialog(
            t("이 용량 변경 기록을 지울까요?", "Delete this dose change record?"),
            isPresented: Binding(
                get: { pendingDoseChangeDeletion != nil },
                set: { if !$0 { pendingDoseChangeDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDoseChangeDeletion
        ) { entry in
            Button(t("지우기", "Delete"), role: .destructive) { deleteDoseChange(entry) }
            Button(t("취소", "Cancel"), role: .cancel) { pendingDoseChangeDeletion = nil }
        }
        .confirmationDialog(
            t("이 메모를 지울까요?", "Delete this note?"),
            isPresented: Binding(
                get: { pendingNoteDeletion != nil },
                set: { if !$0 { pendingNoteDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingNoteDeletion
        ) { note in
            Button(t("지우기", "Delete"), role: .destructive) { deleteNote(note) }
            Button(t("취소", "Cancel"), role: .cancel) { pendingNoteDeletion = nil }
        }
    }

    // MARK: - 카드

    private func headerCard(_ medication: Medication) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                // 이름이 길어 두 줄이 되면 칩이 줄 사이에 어정쩡하게 뜬다.
                // 여기(상세 머리글)는 이름 전체를 보여 주는 유일한 자리라 자르지 않고,
                // 칩을 첫 줄 글줄에 붙여 정렬한다.
                HStack(alignment: .firstTextBaseline, spacing: CGFloat(JanjanSpacing.xs)) {
                    MaskedNameText(name: medication.name, isMasked: masksNames)
                        .janjanDisplay(24)
                        .foregroundStyle(Color.ink)
                    if !medication.strengthText.isEmpty {
                        PillChip(text: medication.strengthText)
                    }
                }
                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    PillChip(text: medication.form.label(lang))
                    PillChip(text: medication.kind.label(lang))
                }
                if !medication.purposeLine.isEmpty {
                    Text(medication.purposeLine)
                        .janjanBody(14)
                        .foregroundStyle(Color.muted)
                        .padding(.top, CGFloat(JanjanSpacing.xxs))
                }
            }
        }
    }

    private func stockCard(_ medication: Medication) -> some View {
        let stock = stockRecords.map(\.core)
        let hasStock = stock.contains { $0.medicationID == medication.id }
        let snapshot = InventoryCalculator.snapshot(
            medicationID: medication.id,
            schedules: scheduleRecords.map(\.core),
            stockEvents: stock,
            doseEvents: doseRecords.map(\.core),
            nextVisit: prescriptionRecords.compactMap { $0.core.nextVisitDate }
                .filter { $0 >= today }.min(),
            asOf: today
        )

        return JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text(t("남은 개수", "Remaining"))
                    .janjanBody(12, weight: .medium)
                    .foregroundStyle(Color.muted)
                if hasStock {
                    // 기록상 소비가 보충보다 많으면 계산이 음수로 떨어진다.
                    // 목록 화면은 0 으로 잡고 "다시 세어 주세요" 를 띄우는데
                    // 여기만 "-4정" 을 그대로 보였다 - 두 화면이 서로 다른
                    // 말을 하면 어느 쪽도 못 믿는다(QA 2026-09-19).
                    let shown = max(snapshot.remaining, 0)
                    Text(t("\(DecimalQuantity.display(shown))정", pillsEn(shown)))
                        .janjanDisplay(28)
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                    if snapshot.remaining < 0 {
                        Text(t(
                            "기록보다 실제로 더 남아 있을 수 있어요. 다시 세어 주세요.",
                            "You may have more left than the records show. Please recount."
                        ))
                            .janjanBody(13)
                            .foregroundStyle(Color.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let refill = StockEvent.lastRefillQuantity(of: medication.id, in: stock) {
                        Text(t("지난 처방에서 받아 온 \(DecimalQuantity.display(refill))정", "Refilled \(pillsEn(refill)) last time"))
                            .janjanBody(13)
                            .foregroundStyle(Color.muted)
                            .monospacedDigit()
                    }
                } else {
                    Text(t("아직 세지 않았어요", "Not counted yet"))
                        .janjanBody(15)
                        .foregroundStyle(Color.muted)
                }

                WhitePillButton(title: t("다시 세기", "Count again"), systemImage: "number") {
                    isShowingRecountSheet = true
                }
                .padding(.top, CGFloat(JanjanSpacing.xxs))
            }
        }
    }

    // MARK: - 필요시 복용

    /// 필요할 때 먹는 약 하나를 그 자리에서 기록하는 줄.
    ///
    /// 정기 약과 달리 시간대가 없어 늘 새 사건으로 쌓인다(DoseRecorder 주석 그대로).
    /// 기본 개수는 이 약을 마지막으로 필요시 먹었을 때의 개수를 따른다 — 없으면 1정.
    private func asNeededCard(_ medication: Medication) -> some View {
        let quantityOptions: [Decimal] = [0.5, 1, 1.5, 2]
        let quantity = selectedAsNeededQuantity ?? defaultAsNeededQuantity

        return JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(t("필요할 때 복용", "As-needed dose"))
                    .janjanBody(15, weight: .medium)
                    .foregroundStyle(Color.ink)

                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    Menu {
                        ForEach(quantityOptions, id: \.self) { option in
                            Button(asNeededQuantityText(option)) {
                                selectedAsNeededQuantity = option
                            }
                        }
                    } label: {
                        PillChip(text: asNeededQuantityText(quantity))
                    }

                    WhitePillButton(title: t("지금 먹었어요", "Took it just now"), systemImage: "checkmark") {
                        recordAsNeededNow(quantity: quantity)
                    }
                }

                if !recentAsNeededRecords.isEmpty {
                    VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                        Text(t("최근 7일", "Last 7 days"))
                            .janjanBody(12, weight: .medium)
                            .foregroundStyle(Color.muted)
                            .padding(.top, CGFloat(JanjanSpacing.xxs))

                        ForEach(recentAsNeededRecords) { record in
                            asNeededRow(record)
                        }
                    }
                }
            }
        }
    }

    private func asNeededRow(_ record: DoseEventRecord) -> some View {
        HStack(alignment: .top, spacing: CGFloat(JanjanSpacing.xs)) {
            Text("\(asNeededTimeText(record.core.effectiveDate)) · \(asNeededQuantityText(record.quantity))")
                .janjanBody(15)
                .foregroundStyle(Color.ink2)
                .monospacedDigit()
            Spacer(minLength: 0)
            Button {
                context.delete(record)
                try? context.save()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.muted)
                    .frame(width: 44, height: 44)
                    // frame 만으로는 투명한 여백이 눌리지 않는다 - 44pt 전체를 판정 영역으로.
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(t("이 기록 지우기", "Delete this record")))
        }
    }

    private var asNeededRecords: [DoseEventRecord] {
        doseRecords.filter {
            $0.medicationID == medicationID && $0.kindRaw == DoseEvent.Kind.asNeeded.rawValue
        }
    }

    /// 이 약을 마지막으로 필요시 먹었을 때의 개수. 한 번도 없으면 nil.
    private var defaultAsNeededQuantity: Decimal {
        asNeededRecords
            .map(\.core)
            .max { $0.effectiveDate < $1.effectiveDate }?
            .quantity ?? 1
    }

    private var recentAsNeededRecords: [DoseEventRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: today) ?? today
        return asNeededRecords
            .filter { $0.core.effectiveDate >= cutoff }
            .sorted { $0.core.effectiveDate > $1.core.effectiveDate }
    }

    private func asNeededQuantityText(_ quantity: Decimal) -> String {
        t("\(DecimalQuantity.display(quantity))정", pillsEn(quantity))
    }

    private func asNeededTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: lang.localeIdentifier)
        formatter.dateFormat = lang == .english ? "MMM d, HH:mm" : "M월 d일 HH:mm"
        return formatter.string(from: date)
    }

    private func recordAsNeededNow(quantity: Decimal) {
        DoseRecorder.recordAsNeeded(medicationID: medicationID, quantity: quantity, source: .phone, in: context)
        try? context.save()
    }

    /// 용량이 바뀐 순간들. **입력만 받는다** — 강점 결정서 D12 그대로,
    /// 이 카드는 계산도 권고도 하지 않는다. "9/3 10mg → 15mg" 을 적어 두면
    /// 해석은 진료실에서 사람이 한다.
    private var doseChangeCard: some View {
        let mine = doseChangeRecords
            .filter { $0.medicationID == medicationID }
            .sorted { $0.changedAt > $1.changedAt }

        return JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(t("용량 변경", "Dose changes"))
                    .janjanBody(15, weight: .medium)
                    .foregroundStyle(Color.ink)

                if mine.isEmpty {
                    Text(t("용량이 바뀌면 여기 적어 두세요. 리포트에 함께 실려요.", "Write it down here when the dose changes. It goes into the report too."))
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(Array(mine.enumerated()), id: \.element.id) { index, entry in
                    // 배지는 맨 위 한 줄에만. 변경이 셋이면 자물쇠도 셋이
                    // 되어 카드가 잠금 표시로 뒤덮인다(TestFlight 17 화면).
                    doseChangeRow(entry, showsProBadge: index == 0)
                }

                // 용량이 실제로 바뀐 바로 그때. 적어 둔 것이 없으면 권하지 않는다.
                if !mine.isEmpty {
                    ProMomentNote(moment: .doseChangeLogged)
                }

                WhitePillButton(title: t("적어 두기", "Write it down"), systemImage: "plus") {
                    isShowingDoseChangeSheet = true
                }
                .padding(.top, CGFloat(JanjanSpacing.xxs))
            }
        }
    }

    private func doseChangeRow(_ entry: DoseChangeRecord, showsProBadge: Bool) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
            HStack(alignment: .top, spacing: CGFloat(JanjanSpacing.xs)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(doseChangeDayText(entry.changedAt)) · \(entry.core.arrowTextKo)")
                        .janjanBody(15)
                        .foregroundStyle(Color.ink2)
                        .monospacedDigit()
                    if let note = entry.note, !note.isEmpty {
                        Text(note)
                            .janjanBody(12)
                            .foregroundStyle(Color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    // 다른 카드처럼 바로 지우지 않고 확인을 한 번 거친다.
                    pendingDoseChangeDeletion = entry
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(t("이 용량 변경 기록 지우기", "Delete this dose change record")))
            }

            WhitePillButton(title: t("약 변경 보기", "See the change")) {
                comparingChange = entry
            }
            .proGated(.doseChangeCompare, showsBadge: showsProBadge)
        }
    }

    private var scheduleCard: some View {
        let mine = scheduleRecords
            .filter { $0.medicationID == medicationID }
            .map(\.core)
            .sorted { $0.timeOfDay < $1.timeOfDay }

        return JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text(t("먹는 때", "When to take it"))
                    .janjanBody(12, weight: .medium)
                    .foregroundStyle(Color.muted)

                if mine.isEmpty {
                    Text(t("정해 둔 시간이 없어요.", "No time set."))
                        .janjanBody(15)
                        .foregroundStyle(Color.muted)
                }

                ForEach(mine) { schedule in
                    HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                        Text(schedule.slot.isCustom
                             ? schedule.timeOfDay.description
                             : "\(schedule.slot.label(lang)) \(schedule.timeOfDay.description)")
                            .janjanBody(15)
                            .foregroundStyle(Color.ink2)
                        PillChip(text: t("\(DecimalQuantity.display(schedule.dosePerIntake))정", pillsEn(schedule.dosePerIntake)))
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    /// 들은 것 · 여쭤볼 것. 같은 모양의 카드 둘이다.
    private func noteCard(_ kind: MedicationNote.Kind) -> some View {
        let notes = myNotes.filter { $0.kindRaw == kind.rawValue }

        return JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(kind.title(lang))
                    .janjanBody(15, weight: .medium)
                    .foregroundStyle(Color.ink)

                if notes.isEmpty {
                    Text(emptyText(kind))
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(notes) { note in
                    noteRow(note)
                }

                WhitePillButton(title: t("적어 두기", "Write it down"), systemImage: "plus") {
                    composing = kind
                }
                .padding(.top, CGFloat(JanjanSpacing.xxs))
            }
        }
    }

    private func emptyText(_ kind: MedicationNote.Kind) -> String {
        switch kind {
        case .heardFromDoctor:
            return t(
                "진료에서 들은 이야기를 적어 두면 잊지 않고, 리포트에 실제 기록과 나란히 나가요.",
                "Write down what you heard at the visit so you don't forget, and it goes into the report alongside your actual records."
            )
        case .questionForDoctor:
            return t(
                "다음 진료에서 여쭤볼 것을 적어 두면 리포트에 함께 나가요.",
                "Write down what to ask at the next visit, and it goes into the report too."
            )
        }
    }

    private func noteRow(_ note: MedicationNoteRecord) -> some View {
        HStack(alignment: .top, spacing: CGFloat(JanjanSpacing.xs)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.text)
                    .janjanBody(15)
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if let symptomID = note.symptomID,
                   let name = Catalogs.symptoms.symptom(id: symptomID)?.name(lang) {
                    // 이름 뒤에 "과/와" 를 직접 붙이면 받침에 따라 틀린다.
                    // 조사를 이름에서 떼어 내 그 문제를 아예 없앤다.
                    Text(t("\(name) 증상과 이어 둠", "Linked to \(name)"))
                        .janjanBody(12)
                        .foregroundStyle(Color.muted)
                }
            }
            Spacer(minLength: 0)
            Button {
                // 메모는 사용자가 직접 쓴 글이라 지우면 되살릴 수 없다.
                // 용량 변경 기록과 같은 규칙으로 확인을 한 번 거친다.
                pendingNoteDeletion = note
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(t("이 메모 지우기", "Delete this note")))
        }
    }

    private func statusCard(_ medication: Medication) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                HStack {
                    Text(t("상태", "Status"))
                        .janjanBody(12, weight: .medium)
                        .foregroundStyle(Color.muted)
                    Spacer()
                    PillChip(text: medication.status.label(lang))
                }
                WhitePillButton(
                    title: medication.status == .active ? t("복용 중단", "Stop taking") : t("다시 복용", "Resume"),
                    systemImage: medication.status == .active ? "pause" : "play"
                ) {
                    MedicationStore.setStatus(
                        medication.status == .active ? .stopped : .active,
                        for: medicationID,
                        in: context
                    )
                    Task { await ReminderPlanner.reschedule(using: context) }
                }
            }
        }
    }

    // MARK: - 저장

    private func addNote(kind: MedicationNote.Kind, text: String, symptomID: String?) {
        let note = MedicationNote(
            medicationID: medicationID,
            kind: kind,
            text: text,
            symptomID: symptomID
        )
        guard !note.isEmpty else { return }
        context.insert(MedicationNoteRecord.make(from: note))
        try? context.save()
    }

    private func saveDoseChange(changedAt: Date, fromText: String, toText: String, note: String?) {
        let change = DoseChange(
            medicationID: medicationID,
            // DatePicker 가 미래를 막지만 저장 규칙은 화면에 기대지 않는다.
            changedAt: min(changedAt, Date()),
            fromText: fromText,
            toText: toText,
            note: note
        )
        context.insert(DoseChangeRecord.make(from: change))
        refreshStrengthText(including: change)
        try? context.save()
    }

    private func deleteNote(_ note: MedicationNoteRecord) {
        context.delete(note)
        pendingNoteDeletion = nil
        try? context.save()
    }

    private func deleteDoseChange(_ entry: DoseChangeRecord) {
        let deletedID = entry.id
        context.delete(entry)
        pendingDoseChangeDeletion = nil
        refreshStrengthText(excluding: deletedID)
        try? context.save()
    }

    /// 머리글의 강도 칩은 **가장 최근 변경의 새 표기**를 따른다.
    ///
    /// 방금 넣은 변경의 값을 무조건 쓰면, 과거 이력을 뒤늦게 보정해 넣었을 때
    /// 표기가 옛 용량으로 퇴행한다(QA 2026-09-10). 잘못 넣은 변경을 지웠을 때도
    /// 같은 규칙으로 되돌린다. 남은 변경이 없으면 표기는 손대지 않는다 —
    /// 등록할 때 적은 값이 그대로 사실이다.
    private func refreshStrengthText(including newChange: DoseChange? = nil, excluding deletedID: UUID? = nil) {
        var changes = doseChangeRecords
            .filter { $0.medicationID == medicationID && $0.id != deletedID }
            .map(\.core)
        if let newChange { changes.append(newChange) }

        let latest = changes.max { lhs, rhs in
            if lhs.changedAt != rhs.changedAt { return lhs.changedAt < rhs.changedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        if let latest {
            record?.strengthText = latest.toText
        }
    }
}

/// 용량 변경 날짜. **리포트와 같은 서식을 쓴다.**
///
/// 예전에는 여기서 따로 만들어(`setLocalizedDateFormatFromTemplate("Md")`)
/// 화면에는 "9. 21." 이, 같은 날이 종이에는 "9월 21일" 로 찍혔다. 둘을
/// 나란히 놓고 보는 사람이 다른 날인 줄 안다(TestFlight 17 화면).
private func doseChangeDayText(_ date: Date) -> String {
    ReportComposer.monthDayText(date, language: JanjanLanguage.current)
}

/// 메모 한 줄을 받는 시트. 증상 카탈로그와 이어 두는 것은 선택이다.
private struct MedicationNoteComposer: View {

    let kind: MedicationNote.Kind
    let onSave: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var symptomID: String?

    private var lang: JanjanLanguage { .current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CGFloat(JanjanSpacing.s)) {
                    JanjanCard {
                        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                            TextField(kind.placeholder(lang), text: $text, axis: .vertical)
                                .janjanBody(16)
                                .foregroundStyle(Color.ink)
                                .lineLimit(1...5)
                            Text(t("들은 말 그대로 적어도 괜찮아요. 앱이 고치지 않아요.", "It's fine to write it exactly as you heard it. The app won't correct it."))
                                .janjanBody(12)
                                .foregroundStyle(Color.muted)
                        }
                    }

                    JanjanCard {
                        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                            Text(t("증상과 이어 둘까요? (선택)", "Link it to a symptom? (optional)"))
                                .janjanBody(13, weight: .medium)
                                .foregroundStyle(Color.ink)
                            Text(t("이어 두면 그 증상을 기록할 때마다 리포트에서 나란히 보여요.", "Once linked, it shows alongside that symptom in the report every time you log it."))
                                .janjanBody(12)
                                .foregroundStyle(Color.muted)
                                .fixedSize(horizontal: false, vertical: true)

                            FlowRow(spacing: CGFloat(JanjanSpacing.xs)) {
                                ForEach(Catalogs.symptoms.symptoms) { item in
                                    let isOn = symptomID == item.id
                                    Button {
                                        symptomID = isOn ? nil : item.id
                                    } label: {
                                        PillChip(
                                            text: item.name(lang),
                                            tint: isOn ? .ink : .surface2,
                                            textTint: isOn ? .surface : .ink2
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : [.isButton])
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.top, CGFloat(JanjanSpacing.s))
                .padding(.bottom, CGFloat(JanjanSpacing.xxl))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle(kind.title(lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(t("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Color.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("저장", "Save")) {
                        onSave(text, symptomID)
                        dismiss()
                    }
                    .foregroundStyle(isSavable ? Color.ink : Color.muted)
                    .disabled(!isSavable)
                }
            }
        }
    }

    private var isSavable: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 용량이 바뀐 날 하나를 받는 시트.
///
/// 계산도 권고도 하지 않는다(강점 결정서 D12) — 날짜와 이전/새 용량,
/// 덧붙일 말만 받아 그대로 적어 둔다.
private struct DoseChangeSheet: View {

    let previousText: String
    let onSave: (Date, String, String, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var changedAt = Date()
    @State private var fromText: String
    @State private var toText = ""
    @State private var note = ""

    init(previousText: String, onSave: @escaping (Date, String, String, String?) -> Void) {
        self.previousText = previousText
        self.onSave = onSave
        _fromText = State(initialValue: previousText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CGFloat(JanjanSpacing.s)) {
                    JanjanCard {
                        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                            Text(t("바뀐 날", "Date changed"))
                                .janjanBody(13, weight: .medium)
                                .foregroundStyle(Color.muted)
                            // 아직 오지 않은 날의 용량은 알 수 없으니 미래는 고를 수 없게 막는다.
                            DatePicker(
                                "",
                                selection: $changedAt,
                                in: ...Date(),
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            .labelsHidden()
                        }
                    }

                    JanjanCard {
                        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                            doseField(label: t("이전", "Previous"), placeholder: "10mg", text: $fromText)
                            doseField(label: t("새 용량", "New dose"), placeholder: "15mg", text: $toText)
                        }
                    }

                    JanjanCard {
                        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                            Text(t("덧붙일 말 (선택)", "Anything to add (optional)"))
                                .janjanBody(13, weight: .medium)
                                .foregroundStyle(Color.ink)
                            TextField("", text: $note, axis: .vertical)
                                .janjanBody(15)
                                .foregroundStyle(Color.ink)
                                .lineLimit(1...4)
                                .padding(CGFloat(JanjanSpacing.s))
                                .background(
                                    RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.row), style: .continuous)
                                        .fill(Color.janjan(.surface2))
                                )
                        }
                    }
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.top, CGFloat(JanjanSpacing.s))
                .padding(.bottom, CGFloat(JanjanSpacing.xxl))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle(t("용량 변경", "Dose changes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(t("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Color.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("저장", "Save")) {
                        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(changedAt, fromText, toText, trimmedNote.isEmpty ? nil : trimmedNote)
                        dismiss()
                    }
                    .foregroundStyle(isSavable ? Color.ink : Color.muted)
                    .disabled(!isSavable)
                }
            }
        }
    }

    private func doseField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
            Text(label)
                .janjanBody(12, weight: .medium)
                .foregroundStyle(Color.muted)
            TextField(placeholder, text: text)
                .janjanBody(16)
                .foregroundStyle(Color.ink)
                .padding(CGFloat(JanjanSpacing.s))
                .background(
                    RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.row), style: .continuous)
                        .fill(Color.janjan(.surface2))
                )
        }
    }

    private var isSavable: Bool {
        !toText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 용량 변경 하나의 전후 2주 비교와, 바꾼 날부터 오늘까지의 체크포인트를
/// 나란히 놓는 시트 (Pro).
///
/// 체크포인트(2026-09-19 결정)는 사용자 제안 그대로다 — 감량·증량은 의사가
/// 계획하고 상태를 봐 가며 하는 것이니 앱은 절대 일정이나 판단을 만들지 않고,
/// 바뀐 날부터 다음 진료까지의 변동을 **따로 모아 보여 주기만** 한다.
/// 여기서도 강점 결정서 D12 그대로다 — 숫자와 사실만 나란히 두고, 좋아졌다·
/// 나빠졌다 같은 말은 붙이지 않는다. 방향은 `DoseChangeComparison.moodText`
/// 가 주는 부호 글자로만 보이고, 색으로는 말하지 않는다.
private struct DoseChangeCompareSheet: View {

    let change: DoseChange
    let medicationName: String
    let masksNames: Bool

    @Environment(\.dismiss) private var dismiss

    // StockRecountSheet 와 같은 패턴 — 걸러 두지 않고 받아서 코어 계산에 그대로 넘긴다.
    @Query private var checkInRecords: [CheckInRecord]
    @Query private var symptomRecords: [SymptomEntryRecord]
    // 체크포인트 타임라인의 재료. 패턴 보기와 같은 계산기를 쓴다.
    @Query private var medicationRecords: [MedicationRecord]
    @Query private var scheduleRecords: [ScheduleRecord]
    @Query private var doseRecords: [DoseEventRecord]
    @Query private var prescriptionRecords: [PrescriptionRecord]

    private var lang: JanjanLanguage { .current }
    private var today: Date { Date() }

    private var comparison: DoseChangeComparison {
        DoseChangeComparison.make(
            change: change,
            checkIns: checkInRecords.map(\.core),
            symptomEntries: symptomRecords.map(\.core)
        )
    }

    /// 바꾼 날부터 오늘까지 며칠째인지 (바꾼 날 = 1일째).
    private var daysSinceChange: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: change.changedAt),
            to: calendar.startOfDay(for: today)
        ).day ?? 0
        return days + 1
    }

    /// 체크포인트 그림. 4주(패턴 보기와 같은 폭)를 넘으면 최근 4주만 그린다.
    private var checkpointTimeline: PatternTimeline {
        PatternTimeline.make(
            dayCount: min(max(daysSinceChange, 1), 28),
            endingAt: today,
            checkIns: checkInRecords.map(\.core),
            schedules: scheduleRecords.map(\.core),
            medications: medicationRecords.map { $0.core.displayReady },
            doseEvents: doseRecords.map(\.core)
        )
    }

    private var nextVisit: Date? {
        prescriptionRecords
            .compactMap { $0.core.nextVisitDate }
            .filter { $0 >= today }
            .min()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CGFloat(JanjanSpacing.s)) {
                    JanjanCard {
                        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                            MaskedNameText(name: medicationName, isMasked: masksNames)
                                .janjanBody(17, weight: .semibold)
                                .foregroundStyle(Color.ink)
                            Text("\(doseChangeDayText(change.changedAt)) · \(change.arrowTextKo)")
                                .janjanBody(13)
                                .foregroundStyle(Color.muted)
                                .monospacedDigit()
                        }
                    }

                    JanjanCard {
                        Text(t(
                            "변경 전 2주와 후 2주의 기록을 그대로 놓았어요. 해석은 진료에서 함께 하시면 돼요.",
                            "The two weeks before and after are laid out as recorded. You can go over what it means together at your visit."
                        ))
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    JanjanCard {
                        if comparison.hasAnything {
                            compareTable
                        } else {
                            Text(t("이 구간에는 아직 기록이 없어요.", "There are no records in this period yet."))
                                .janjanBody(15)
                                .foregroundStyle(Color.muted)
                        }
                    }

                    // 체크포인트: 바꾼 날부터 오늘까지의 흐름을 따로 모은다.
                    PatternCard(
                        timeline: checkpointTimeline,
                        isLocked: false,
                        title: t("변경 후 흐름", "Since the change"),
                        subtitle: daysSinceChange > 28
                            ? t("바꾼 지 4주가 넘어 최근 4주만 보여요.", "It's been over 4 weeks, so this shows the latest 4.")
                            : t("바꾼 날부터 오늘까지의 기분·복약·수면이에요.", "Mood, doses, and sleep from the change to today.")
                    )

                    if let nextVisit {
                        JanjanCard {
                            Text(nextVisitLine(nextVisit))
                                .janjanBody(13)
                                .foregroundStyle(Color.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.top, CGFloat(JanjanSpacing.s))
                .padding(.bottom, CGFloat(JanjanSpacing.xxl))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle(t("약 변경 보기", "See the change"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(t("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
        }
    }

    /// 다음 진료가 잡혀 있으면 그 흐름을 언제 같이 볼지 한 줄로 잇는다.
    /// 날짜 계산만 하고 판단은 하지 않는다.
    private func nextVisitLine(_ visit: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: today),
            to: calendar.startOfDay(for: visit)
        ).day ?? 0
        if days == 0 {
            return t("오늘이 진료일이에요. 이 흐름을 함께 보시면 돼요.",
                     "Your visit is today. You can go over this together.")
        }
        return t("다음 진료까지 \(days)일. 이 흐름을 그날 함께 보시면 돼요.",
                 "\(days) days to your next visit. You can go over this together then.")
    }

    // MARK: - 표
    //
    // 좁은 화면(SE, 375pt)에서도 넘치지 않는지: 열 셋 다 숫자·짧은 단어뿐이라
    // Grid 가 내용에 맞춰 폭을 잡으면 카드 안쪽 폭(대략 310pt)에 넉넉히 들어간다.

    private var compareTable: some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
            // 값 열 둘에 maxWidth 를 줘서 카드 폭 전체에 고르게 편다 - 내용에 맞춰
            // 움츠러들면 표가 왼쪽에 몰리고 오른쪽이 빈다(사용자 발견 2026-09-16).
            Grid(alignment: .leading, horizontalSpacing: CGFloat(JanjanSpacing.s), verticalSpacing: CGFloat(JanjanSpacing.s)) {
                GridRow {
                    Text("")
                    Text(t("변경 전 \(comparison.before.days)일", "Before · \(comparison.before.days) days"))
                        .janjanBody(12, weight: .medium)
                        .foregroundStyle(Color.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(t("변경 후 \(comparison.after.days)일", "After · \(comparison.after.days) days"))
                        .janjanBody(12, weight: .medium)
                        .foregroundStyle(Color.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                metricRow(
                    label: t("기분 평균", "Mood average"),
                    before: moodCell(comparison.before),
                    after: moodCell(comparison.after)
                )
                metricRow(
                    label: t("수면 평균", "Sleep average"),
                    before: sleepCell(comparison.before),
                    after: sleepCell(comparison.after)
                )
                metricRow(
                    label: t("증상 기록", "Symptoms"),
                    before: symptomCell(comparison.before),
                    after: symptomCell(comparison.after)
                )
                metricRow(
                    label: t("꿈", "Dreams"),
                    before: dreamCell(comparison.before),
                    after: dreamCell(comparison.after)
                )
            }

            if comparison.after.days < DoseChangeComparison.windowDays {
                Text(t(
                    "변경한 지 \(comparison.after.days)일이 지났어요. \(DoseChangeComparison.windowDays)일이 모이면 앞뒤를 같은 길이로 비교해요.",
                    "It's been \(comparison.after.days) days since the change. Once \(DoseChangeComparison.windowDays) days are in, both sides compare at equal length."
                ))
                .janjanBody(12)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func metricRow<Before: View, After: View>(label: String, before: Before, after: After) -> some View {
        GridRow {
            Text(label)
                .janjanBody(13)
                .foregroundStyle(Color.ink2)
            before
                .frame(maxWidth: .infinity, alignment: .leading)
            after
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func moodCell(_ window: DoseChangeComparison.Window) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(DoseChangeComparison.moodText(window.moodAverage) ?? t("기록 없음", "No records"))
                .janjanBody(15, weight: .medium)
                .foregroundStyle(Color.ink)
                .monospacedDigit()
            Text(t("\(window.moodRecordedDays)일 기록", "\(window.moodRecordedDays) days recorded"))
                .janjanBody(11)
                .foregroundStyle(Color.muted)
                .monospacedDigit()
        }
    }

    private func sleepCell(_ window: DoseChangeComparison.Window) -> some View {
        Text(DoseChangeComparison.sleepText(window.sleepAverageMinutes, language: lang) ?? t("기록 없음", "No records"))
            .janjanBody(15, weight: .medium)
            .foregroundStyle(Color.ink)
            .monospacedDigit()
    }

    private func symptomCell(_ window: DoseChangeComparison.Window) -> some View {
        Text(t("\(window.symptomDays)일", "\(window.symptomDays) days"))
            .janjanBody(15, weight: .medium)
            .foregroundStyle(Color.ink)
            .monospacedDigit()
    }

    /// 두 줄로 나눈다 - 한 줄("0일 · 악몽 0일")은 좁은 화면에서 카드 오른쪽 끝에
    /// 닿아 있어서, 숫자가 두 자리가 되는 순간 잘린다(사용자 발견 2026-09-16).
    private func dreamCell(_ window: DoseChangeComparison.Window) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t("\(window.dreamDays)일", "\(window.dreamDays) days"))
                .janjanBody(15, weight: .medium)
                .foregroundStyle(Color.ink)
                .monospacedDigit()
            Text(t("악몽 \(window.nightmareDays)일", "nightmares \(window.nightmareDays)"))
                .janjanBody(11)
                .foregroundStyle(Color.muted)
                .monospacedDigit()
        }
    }
}

/// 재고를 다시 세어 기록과 맞춰 보는 시트.
///
/// 여기서 만드는 사건은 언제나 **정정(correction)** 이다 — 재고 계산 원칙(설계 05절)대로
/// 이 시점이 새 기준점이 되고 그 이전 사건은 계산에서 빠진다. 판단은 하지 않는다:
/// 실제 개수와 기록상 잔여를 나란히 보여 주고 차이만 말한다.
private struct StockRecountSheet: View {

    let medicationID: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var scheduleRecords: [ScheduleRecord]
    @Query private var doseRecords: [DoseEventRecord]
    @Query private var stockRecords: [StockEventRecord]
    @Query private var medicationRecords: [MedicationRecord]

    @State private var countedText = ""

    private var lang: JanjanLanguage { .current }
    private var now: Date { Date() }

    private var stockEvents: [StockEvent] { stockRecords.map(\.core) }
    private var doseEvents: [DoseEvent] { doseRecords.map(\.core) }
    private var schedules: [Schedule] { scheduleRecords.map(\.core) }
    private var medications: [Medication] { medicationRecords.map { $0.core.displayReady } }

    /// 기록상 잔여. 이 화면의 재고 카드와 같은 계산기를 쓴다.
    private var remaining: Decimal {
        InventoryCalculator.remaining(
            for: medicationID,
            stockEvents: stockEvents,
            doseEvents: doseEvents,
            asOf: now
        )
    }

    /// "1.5", "1,5" 둘 다 받는다. 숫자가 아니면 아직 세지 않은 것으로 본다.
    private var countedQuantity: Decimal? {
        let trimmed = countedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty, let value = Decimal(string: trimmed), value >= 0 else { return nil }
        return DecimalQuantity.snapToQuarter(value)
    }

    /// 계산만 한다 — "빠트렸다" 고 말하지 않는다.
    private var comparisonText: String? {
        guard let counted = countedQuantity else { return nil }
        let diff = DecimalQuantity.round(counted - remaining, scale: 2)
        if diff == 0 {
            return t("기록과 맞아요.", "Matches the record.")
        } else if diff > 0 {
            return t(
                "기록보다 \(DecimalQuantity.display(diff))정 많아요. 보충을 적지 않았거나, 기록만 하고 드시지 않은 날이 있을 수 있어요.",
                "It's \(pillsEn(diff)) more than the record. A refill may not have been logged, or there may be a day it was recorded as taken but wasn't."
            )
        } else {
            let shortfall = DecimalQuantity.round(remaining - counted, scale: 2)
            return t(
                "기록보다 \(DecimalQuantity.display(shortfall))정 적어요. 기록 없이 드신 날이 있을 수 있어요.",
                "It's \(pillsEn(shortfall)) less than the record. There may be a day it was taken without being recorded."
            )
        }
    }

    /// 이 약의 마지막 **직접 정정** 시각. 한 번도 없으면 7일 전부터 본다.
    ///
    /// 보충(refill)은 기준점을 세우지 않는다 - remaining() 은 마지막 정정부터의
    /// 소비를 전부 세므로, 그 사이에 보충이 있었어도 미기록 시간대는 정정
    /// 이후 전체에서 찾아야 차이의 원인 후보를 놓치지 않는다.
    private var unrecordedFrom: Date {
        let lastCorrection = stockEvents
            .filter { $0.medicationID == medicationID && $0.isCorrection }
            .map(\.occurredAt)
            .max()
        return lastCorrection ?? (Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now)
    }

    /// 이 약만 걸러 낸, 기록 없이 지나간 시간대.
    private var unrecordedLines: [UnrecordedSlots.Line] {
        UnrecordedSlots.find(
            from: unrecordedFrom,
            until: now,
            schedules: schedules,
            medications: medications,
            doseEvents: doseEvents
        )
        .compactMap { line in
            let mine = line.entries.filter { $0.medicationID == medicationID }
            guard !mine.isEmpty else { return nil }
            return UnrecordedSlots.Line(day: line.day, slot: line.slot, plannedAt: line.plannedAt, entries: mine)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CGFloat(JanjanSpacing.s)) {
                    JanjanCard {
                        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                            Text(t("기록상 잔여", "On record"))
                                .janjanBody(12, weight: .medium)
                                .foregroundStyle(Color.muted)
                            // 바로 위 라벨이 이미 "기록상 잔여" 라고 말한다.
                            // 값에 다시 붙이면 영어가 "On record / On record:
                            // 17 pills" 로 두 번 읽힌다(영어 캡처 2026-09-20).
                            Text(t(
                                "\(DecimalQuantity.display(remaining))정",
                                pillsEn(remaining)
                            ))
                                .janjanDisplay(24)
                                .foregroundStyle(Color.ink)
                                .monospacedDigit()
                        }
                    }

                    JanjanCard {
                        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                            JanjanField(
                                label: t("실제로 센 개수", "Count you actually have"),
                                placeholder: t("예: 20", "e.g. 20"),
                                keyboard: .decimalPad,
                                text: $countedText
                            )
                            if let comparisonText {
                                Text(comparisonText)
                                    .janjanBody(13)
                                    .foregroundStyle(Color.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if !unrecordedLines.isEmpty {
                        JanjanCard {
                            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                                Text(t("기록 없이 지나간 시간대", "Slots that passed unrecorded"))
                                    .janjanBody(15, weight: .medium)
                                    .foregroundStyle(Color.ink)
                                Text(t(
                                    "어느 날인지 기억나면 골라 주세요. 기억나지 않아도 괜찮아요 — 방금 센 개수가 새 기준이 됩니다.",
                                    "Pick the day if you remember. If not, that's okay — the count you just made becomes the new baseline."
                                ))
                                    .janjanBody(12)
                                    .foregroundStyle(Color.muted)
                                    .fixedSize(horizontal: false, vertical: true)

                                ForEach(unrecordedLines) { line in
                                    unrecordedRow(line)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.top, CGFloat(JanjanSpacing.s))
                .padding(.bottom, CGFloat(JanjanSpacing.xxl))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle(t("다시 세기", "Count again"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(t("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Color.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("이 개수로 맞추기", "Set to this count")) {
                        save()
                    }
                    .foregroundStyle(countedQuantity != nil ? Color.ink : Color.muted)
                    .disabled(countedQuantity == nil)
                }
            }
        }
    }

    private func unrecordedRow(_ line: UnrecordedSlots.Line) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
            Text(UnrecordedSlots.title(for: line, language: lang))
                .janjanBody(15)
                .foregroundStyle(Color.ink2)

            // 오늘 화면의 같은 세 답과 같은 줄을 쓴다. 셋이 늘 한 줄이고,
            // 흰 카드 위라 흰 알약 대신 한 겹 어두운 면을 쓴다.
            AnswerPillRow(answers: [
                .init(t("먹었어요", "Took it")) { respond(to: line, status: .taken) },
                .init(t("건너뛰었어요", "Skipped it")) { respond(to: line, status: .skipped) },
                .init(t("기억나지 않아요", "I don't remember")) { respond(to: line, status: .unrecorded) }
            ])
        }
        .padding(.vertical, CGFloat(JanjanSpacing.xxs))
    }

    /// 여기서 답하면 그 시간대의 기록이 생겨 기록상 잔여가 바로 바뀐다 —
    /// 위 비교 문장도 같은 화면에서 다시 계산된다.
    private func respond(to line: UnrecordedSlots.Line, status: DoseEvent.Status) {
        DoseRecorder.record(
            medicationID: medicationID,
            slotKey: line.slot.storageKey,
            status: status,
            source: .phone,
            on: line.day,
            at: line.plannedAt,
            in: context
        )
        try? context.save()
    }

    private func save() {
        guard let counted = countedQuantity else { return }
        let event = StockEvent.correction(medicationID: medicationID, setTo: counted, at: Date(), note: nil)
        context.insert(StockEventRecord.make(from: event))
        try? context.save()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        MedicationDetailView(medicationID: UUID())
    }
    .environmentObject(ProStore())
    .modelContainer(for: JanjanSchema.allModels, inMemory: true)
}
