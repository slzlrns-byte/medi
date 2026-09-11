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
    @State private var selectedAsNeededQuantity: Decimal?
    @State private var isShowingRecountSheet = false

    private var today: Date { Date() }
    private var lang: JanjanLanguage { .current }

    private var record: MedicationRecord? {
        medicationRecords.first { $0.id == medicationID }
    }

    private var medication: Medication? { record?.core }

    private var myNotes: [MedicationNoteRecord] {
        noteRecords.filter { $0.medicationID == medicationID }
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
        .navigationTitle(medication?.name ?? t("약", "Medication"))
        .navigationBarTitleDisplayMode(.inline)
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
    }

    // MARK: - 카드

    private func headerCard(_ medication: Medication) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    Text(medication.name)
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
                    Text(t("\(DecimalQuantity.display(snapshot.remaining))정", "\(DecimalQuantity.display(snapshot.remaining)) pills"))
                        .janjanDisplay(28)
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                    if let refill = StockEvent.lastRefillQuantity(of: medication.id, in: stock) {
                        Text(t("지난 처방에서 받아 온 \(DecimalQuantity.display(refill))정", "Refilled \(DecimalQuantity.display(refill)) pills last time"))
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
        t("\(DecimalQuantity.display(quantity))정", "\(DecimalQuantity.display(quantity)) pills")
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

                ForEach(mine) { entry in
                    doseChangeRow(entry)
                }

                WhitePillButton(title: t("적어 두기", "Write it down"), systemImage: "plus") {
                    isShowingDoseChangeSheet = true
                }
                .padding(.top, CGFloat(JanjanSpacing.xxs))
            }
        }
    }

    private func doseChangeRow(_ entry: DoseChangeRecord) -> some View {
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(t("이 용량 변경 기록 지우기", "Delete this dose change record")))
        }
    }

    private func doseChangeDayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: JanjanLanguage.current.localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
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
                        PillChip(text: t("\(DecimalQuantity.display(schedule.dosePerIntake))정", "\(DecimalQuantity.display(schedule.dosePerIntake)) pills"))
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
                context.delete(note)
                try? context.save()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.muted)
                    .frame(width: 44, height: 44)
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
    private var medications: [Medication] { medicationRecords.map(\.core) }

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
                "It's \(DecimalQuantity.display(diff)) pills more than the record. A refill may not have been logged, or there may be a day it was recorded as taken but wasn't."
            )
        } else {
            let shortfall = DecimalQuantity.round(remaining - counted, scale: 2)
            return t(
                "기록보다 \(DecimalQuantity.display(shortfall))정 적어요. 기록 없이 드신 날이 있을 수 있어요.",
                "It's \(DecimalQuantity.display(shortfall)) pills less than the record. There may be a day it was taken without being recorded."
            )
        }
    }

    /// 이 약의 마지막 재고 사건(보충 또는 정정) 시각. 한 번도 없으면 7일 전부터 본다.
    private var unrecordedFrom: Date {
        let lastStockEvent = stockEvents
            .filter { $0.medicationID == medicationID }
            .map(\.occurredAt)
            .max()
        return lastStockEvent ?? (Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now)
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
                            Text(t(
                                "기록상 \(DecimalQuantity.display(remaining))정",
                                "On record: \(DecimalQuantity.display(remaining)) pills"
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

            // 오늘 화면의 같은 세 답과 같은 크기(44pt 터치 타깃)를 쓴다.
            FlowRow(spacing: CGFloat(JanjanSpacing.xs)) {
                WhitePillButton(title: t("먹었어요", "Took it")) {
                    respond(to: line, status: .taken)
                }
                WhitePillButton(title: t("건너뛰었어요", "Skipped it")) {
                    respond(to: line, status: .skipped)
                }
                WhitePillButton(title: t("기억나지 않아요", "I don't remember")) {
                    respond(to: line, status: .unrecorded)
                }
            }
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
    .modelContainer(for: JanjanSchema.allModels, inMemory: true)
}
