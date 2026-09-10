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

    private var today: Date { Date() }

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
                    doseChangeCard
                    scheduleCard
                    noteCard(.heardFromDoctor)
                    noteCard(.questionForDoctor)
                    statusCard(medication)
                } else {
                    // 다른 화면에서 지운 뒤 이 화면이 남아 있는 경우.
                    JanjanCard {
                        Text("이 약은 지워졌어요.")
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
        .navigationTitle(medication?.name ?? "약")
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
        .confirmationDialog(
            "이 용량 변경 기록을 지울까요?",
            isPresented: Binding(
                get: { pendingDoseChangeDeletion != nil },
                set: { if !$0 { pendingDoseChangeDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDoseChangeDeletion
        ) { entry in
            Button("지우기", role: .destructive) { deleteDoseChange(entry) }
            Button("취소", role: .cancel) { pendingDoseChangeDeletion = nil }
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
                    PillChip(text: medication.form.labelKo)
                    PillChip(text: medication.kind.labelKo)
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
                Text("남은 개수")
                    .janjanBody(12, weight: .medium)
                    .foregroundStyle(Color.muted)
                if hasStock {
                    Text("\(DecimalQuantity.display(snapshot.remaining))정")
                        .janjanDisplay(28)
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                    if let refill = StockEvent.lastRefillQuantity(of: medication.id, in: stock) {
                        Text("지난 처방에서 받아 온 \(DecimalQuantity.display(refill))정")
                            .janjanBody(13)
                            .foregroundStyle(Color.muted)
                            .monospacedDigit()
                    }
                } else {
                    Text("아직 세지 않았어요")
                        .janjanBody(15)
                        .foregroundStyle(Color.muted)
                }
            }
        }
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
                Text("용량 변경")
                    .janjanBody(15, weight: .medium)
                    .foregroundStyle(Color.ink)

                if mine.isEmpty {
                    Text("용량이 바뀌면 여기 적어 두세요. 리포트에 함께 실려요.")
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(mine) { entry in
                    doseChangeRow(entry)
                }

                WhitePillButton(title: "적어 두기", systemImage: "plus") {
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
            .accessibilityLabel(Text("이 용량 변경 기록 지우기"))
        }
    }

    private func doseChangeDayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
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
                Text("먹는 때")
                    .janjanBody(12, weight: .medium)
                    .foregroundStyle(Color.muted)

                if mine.isEmpty {
                    Text("정해 둔 시간이 없어요.")
                        .janjanBody(15)
                        .foregroundStyle(Color.muted)
                }

                ForEach(mine) { schedule in
                    HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                        Text(schedule.slot.isCustom
                             ? schedule.timeOfDay.description
                             : "\(schedule.slot.labelKo) \(schedule.timeOfDay.description)")
                            .janjanBody(15)
                            .foregroundStyle(Color.ink2)
                        PillChip(text: "\(DecimalQuantity.display(schedule.dosePerIntake))정")
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
                Text(kind.titleKo)
                    .janjanBody(15, weight: .medium)
                    .foregroundStyle(Color.ink)

                if notes.isEmpty {
                    Text(emptyTextKo(kind))
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(notes) { note in
                    noteRow(note)
                }

                WhitePillButton(title: "적어 두기", systemImage: "plus") {
                    composing = kind
                }
                .padding(.top, CGFloat(JanjanSpacing.xxs))
            }
        }
    }

    private func emptyTextKo(_ kind: MedicationNote.Kind) -> String {
        switch kind {
        case .heardFromDoctor:
            return "진료에서 들은 이야기를 적어 두면 잊지 않고, 리포트에 실제 기록과 나란히 나가요."
        case .questionForDoctor:
            return "다음 진료에서 여쭤볼 것을 적어 두면 리포트에 함께 나가요."
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
                   let name = Catalogs.symptoms.symptom(id: symptomID)?.nameKo {
                    // 이름 뒤에 "과/와" 를 직접 붙이면 받침에 따라 틀린다.
                    // 조사를 이름에서 떼어 내 그 문제를 아예 없앤다.
                    Text("\(name) 증상과 이어 둠")
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
            .accessibilityLabel(Text("이 메모 지우기"))
        }
    }

    private func statusCard(_ medication: Medication) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                HStack {
                    Text("상태")
                        .janjanBody(12, weight: .medium)
                        .foregroundStyle(Color.muted)
                    Spacer()
                    PillChip(text: medication.status.labelKo)
                }
                WhitePillButton(
                    title: medication.status == .active ? "복용 중단" : "다시 복용",
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
            changedAt: changedAt,
            fromText: fromText,
            toText: toText,
            note: note
        )
        context.insert(DoseChangeRecord.make(from: change))
        // 지금 먹는 용량 표기도 함께 갱신한다 — 안 그러면 머리글의 강도 칩이
        // 방금 적어 둔 변경과 어긋나 버린다.
        record?.strengthText = change.toText
        try? context.save()
    }

    private func deleteDoseChange(_ entry: DoseChangeRecord) {
        context.delete(entry)
        pendingDoseChangeDeletion = nil
        try? context.save()
    }
}

/// 메모 한 줄을 받는 시트. 증상 카탈로그와 이어 두는 것은 선택이다.
private struct MedicationNoteComposer: View {

    let kind: MedicationNote.Kind
    let onSave: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var symptomID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CGFloat(JanjanSpacing.s)) {
                    JanjanCard {
                        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                            TextField(kind.placeholderKo, text: $text, axis: .vertical)
                                .janjanBody(16)
                                .foregroundStyle(Color.ink)
                                .lineLimit(1...5)
                            Text("들은 말 그대로 적어도 괜찮아요. 앱이 고치지 않아요.")
                                .janjanBody(12)
                                .foregroundStyle(Color.muted)
                        }
                    }

                    JanjanCard {
                        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                            Text("증상과 이어 둘까요? (선택)")
                                .janjanBody(13, weight: .medium)
                                .foregroundStyle(Color.ink)
                            Text("이어 두면 그 증상을 기록할 때마다 리포트에서 나란히 보여요.")
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
                                            text: item.nameKo,
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
            .navigationTitle(kind.titleKo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(Color.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") {
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
                            Text("바뀐 날")
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
                            doseField(label: "이전", placeholder: "10mg", text: $fromText)
                            doseField(label: "새 용량", placeholder: "15mg", text: $toText)
                        }
                    }

                    JanjanCard {
                        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                            Text("덧붙일 말 (선택)")
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
            .navigationTitle("용량 변경")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(Color.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") {
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

#Preview {
    NavigationStack {
        MedicationDetailView(medicationID: UUID())
    }
    .modelContainer(for: JanjanSchema.allModels, inMemory: true)
}
