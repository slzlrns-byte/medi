import SwiftUI
import SwiftData
import JanjanCore

/// 처방 기록 (설계 03절 · 05절).
///
/// 이 화면 하나가 "다음 진료 D-" 와 "진료 전에 모자라는 약" 을 살린다.
/// 둘 다 진료일과 받아 온 개수를 알아야 계산할 수 있기 때문이다.
///
/// 개수는 **제안일 뿐 강요가 아니다.** 처방일수 × 하루 예정 개수로 초안을 채워 두고
/// 사용자가 실제로 받아 온 수로 고칠 수 있게 한다. 봉투에 적힌 수와 손에 쥔 수는 자주 다르다.
struct PrescriptionFormView: View {

    let onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var pro: ProStore

    @Query(sort: \MedicationRecord.createdAt) private var medicationRecords: [MedicationRecord]
    @Query private var scheduleRecords: [ScheduleRecord]
    @Query private var stockRecords: [StockEventRecord]

    @State private var visitDate = Date()
    @State private var daysSupplied = 28
    @State private var hasNextVisit = true
    @State private var nextVisitDate = Date()
    @State private var clinicNote = ""
    /// 약 id → 받아 온 개수. 여기 없으면 이번 처방에 없는 약이다.
    @State private var refills: [UUID: Decimal] = [:]
    @State private var isSaving = false
    /// 사용자가 개수를 직접 고친 약. 제안값을 다시 덮어쓰지 않으려고 기억해 둔다.
    @State private var edited: Set<UUID> = []

    init(onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        let today = Date()
        _visitDate = State(initialValue: today)
        _nextVisitDate = State(
            initialValue: Calendar.current.date(byAdding: .day, value: 28, to: today) ?? today
        )
    }

    private var activeMedications: [Medication] {
        medicationRecords.map(\.core).filter { $0.status == .active }
    }

    private var schedules: [Schedule] { scheduleRecords.map(\.core) }

    /// 약 이름 가리기가 실제로 적용되는지. Pro 가 아니면 켜져 있어도 아무 일도 하지 않는다.
    private var masksNames: Bool { pro.isPro && JanjanPrivacy.hidesNames }

    var body: some View {
        ScrollView {
            VStack(spacing: CGFloat(JanjanSpacing.s)) {
                visitCard
                if activeMedications.isEmpty {
                    emptyCard
                } else {
                    medicationCard
                }
                noteCard
                if let warning = staleDateWarning {
                    JanjanCard {
                        Text(warning)
                            .janjanBody(13)
                            .foregroundStyle(Color.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                BlackPillButton(title: t("저장", "Save"), isBusy: isSaving, isEnabled: canSave) {
                    save()
                }
                .padding(.top, CGFloat(JanjanSpacing.s))

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
        .navigationTitle(t("처방 기록", "Log a prescription"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 카드

    private var visitCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
                DatePicker(
                    t("진료 받은 날", "Visit date"),
                    selection: $visitDate,
                    displayedComponents: .date
                )
                .janjanBody(15)
                .tint(Color.ink)
                .onChange(of: visitDate) { _, _ in refreshSuggestions() }

                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                    Text(t("며칠치를 받았어요?", "How many days' worth did you get?"))
                        .janjanBody(12, weight: .medium)
                        .foregroundStyle(Color.muted)
                    CountStepper(
                        text: t("\(daysSupplied)일치", "\(daysSupplied) days"),
                        decreaseLabelKo: t("처방 일수 줄이기", "Decrease days supplied"),
                        increaseLabelKo: t("처방 일수 늘리기", "Increase days supplied"),
                        onDecrease: { changeDays(by: -7) },
                        onIncrease: { changeDays(by: 7) }
                    )
                }

                Toggle(t("다음 진료일이 정해졌어요", "Next visit date is set"), isOn: $hasNextVisit)
                    .janjanBody(15)
                    .tint(Color.ink)

                if hasNextVisit {
                    DatePicker(
                        t("다음 진료", "Next visit"),
                        selection: $nextVisitDate,
                        in: visitDate...,
                        displayedComponents: .date
                    )
                    .janjanBody(15)
                    .tint(Color.ink)
                }
            }
        }
    }

    private var emptyCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text(t("등록된 약이 없어요", "No medications registered"))
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)
                Text(t("약을 먼저 등록하면 여기서 받아 온 개수를 함께 적을 수 있어요. 진료일만 먼저 남겨도 괜찮아요.", "Register a medication first and you can log how much you picked up here too. It's fine to just save the visit date for now."))
                    .janjanBody(13)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var medicationCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(t("이번에 받아 온 약", "Medications picked up this time"))
                    .janjanBody(12, weight: .medium)
                    .foregroundStyle(Color.muted)

                ForEach(activeMedications) { medication in
                    medicationRow(medication)
                }
            }
        }
    }

    private func medicationRow(_ medication: Medication) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
            HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                togglePill(for: medication)
                Spacer(minLength: 0)
            }

            if let quantity = refills[medication.id] {
                CountStepper(
                    text: t("\(DecimalQuantity.display(quantity))정", "\(DecimalQuantity.display(quantity)) pills"),
                    decreaseLabelKo: t("\(medication.name) 개수 줄이기", "Decrease \(medication.name) count"),
                    increaseLabelKo: t("\(medication.name) 개수 늘리기", "Increase \(medication.name) count"),
                    onDecrease: { adjust(medication, by: -1) },
                    onIncrease: { adjust(medication, by: 1) }
                )
            }
        }
        .padding(.vertical, CGFloat(JanjanSpacing.xxs))
    }

    /// 이 알약은 눌러서 이번 처방에 포함시키는 손잡이다 - 이름 자리에 따로 탭을
    /// 두면 손잡이 전체의 탭(선택 · 해제)과 겹친다. 그래서 `MaskedNameText` 대신
    /// 가려졌을 때는 점 표기만 보여 주고, 다시 눌러 보이게 하는 동작은 두지 않는다
    /// (약 목록 행과 같은 판단 - `MedicationsView.medicationNameText` 참고).
    @ViewBuilder
    private func togglePill(for medication: Medication) -> some View {
        if masksNames {
            // 여러 약이 전부 점이면 어느 것을 고르는지 알 수 없다. 목록 행과 같은
            // 규칙으로 용도 한 줄이 있으면 그것으로 부른다.
            TogglePill(
                text: medication.purposeLine.isEmpty ? MaskedNameText.maskGlyph : medication.purposeLine,
                isOn: refills[medication.id] != nil
            ) {
                toggle(medication)
            }
            .accessibilityLabel(Text(t("가려진 약 이름", "Hidden medication name")))
        } else {
            TogglePill(
                text: medication.displayTitle,
                isOn: refills[medication.id] != nil
            ) {
                toggle(medication)
            }
        }
    }

    private var noteCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                JanjanField(
                    label: t("진료 메모 (선택)", "Visit note (optional)"),
                    placeholder: t("예: 용량 절반으로", "e.g. Cut the dose in half"),
                    text: $clinicNote
                )
                Text(t("들은 말을 그대로 적어 두면 다음 진료에서 되짚기 쉬워요.", "Writing down what you heard, as is, makes it easy to revisit at the next visit."))
                    .janjanBody(12)
                    .foregroundStyle(Color.muted)
            }
        }
    }

    // MARK: - 규칙

    /// 진료일만 있어도 저장된다. 약을 아직 안 넣었어도 "다음 진료 D-" 는 살아난다.
    private var canSave: Bool { !isSaving }

    /// 재고 계산은 **마지막 직접 정정**을 기준점으로 삼고 그 이전 사건을 전부 버린다(설계 05절).
    /// 그래서 정정보다 앞선 날짜로 보충을 넣으면 개수가 하나도 안 늘어난다.
    /// 규칙 자체는 옳지만, 아무 말 없이 삼켜 버리면 사용자는 앱이 고장 났다고 생각한다.
    private var staleDateWarning: String? {
        let chosen = Set(refills.filter { $0.value > 0 }.keys)
        guard !chosen.isEmpty else { return nil }

        let blocked = stockRecords
            .filter { chosen.contains($0.medicationID) && $0.core.isCorrection }
            .filter { $0.occurredAt > visitDate }

        guard !blocked.isEmpty else { return nil }
        return t(
            "고른 약 중에 진료일 뒤에 재고를 직접 센 기록이 있어요. "
                + "재고는 마지막으로 센 개수가 기준이라, 그보다 앞선 보충은 개수에 더해지지 않아요.",
            "One of the medications you chose has a stock count recorded after this visit date. "
                + "Since stock is based on the most recent count, a refill dated earlier than that won't be added."
        )
    }

    private func changeDays(by delta: Int) {
        let previous = daysSupplied
        daysSupplied = min(max(daysSupplied + delta, 1), 365)

        // 다음 진료일을 사용자가 따로 만지지 않았다면 처방일수를 따라가게 둔다.
        if let suggested = Calendar.current.date(byAdding: .day, value: previous, to: visitDate),
           Calendar.current.isDate(nextVisitDate, inSameDayAs: suggested) {
            nextVisitDate = Calendar.current
                .date(byAdding: .day, value: daysSupplied, to: visitDate) ?? nextVisitDate
        }
        refreshSuggestions()
    }

    private func toggle(_ medication: Medication) {
        if refills[medication.id] != nil {
            refills[medication.id] = nil
            edited.remove(medication.id)
        } else {
            refills[medication.id] = suggestedQuantity(for: medication)
        }
    }

    private func adjust(_ medication: Medication, by delta: Decimal) {
        guard let current = refills[medication.id] else { return }
        refills[medication.id] = max(current + delta, 0)
        edited.insert(medication.id)
    }

    /// 처방일수 × 하루 예정 개수. 스케줄이 없으면 하루 1정으로 본다.
    private func suggestedQuantity(for medication: Medication) -> Decimal {
        let mine = schedules.filter { $0.medicationID == medication.id }
        let daily = mine.dailyScheduledQuantity()
        let perDay = daily > 0 ? daily : 1
        return DecimalQuantity.snapToQuarter(Decimal(daysSupplied) * perDay)
    }

    /// 처방일수나 진료일이 바뀌면 제안값을 다시 계산한다.
    /// 사용자가 직접 고친 약은 건드리지 않는다.
    private func refreshSuggestions() {
        for medication in activeMedications where refills[medication.id] != nil {
            guard !edited.contains(medication.id) else { continue }
            refills[medication.id] = suggestedQuantity(for: medication)
        }
    }

    // MARK: - 저장

    private func save() {
        guard canSave else { return }
        isSaving = true

        let chosen = refills.filter { $0.value > 0 }

        let prescription = Prescription(
            visitDate: visitDate,
            daysSupplied: daysSupplied,
            nextVisitDate: hasNextVisit ? nextVisitDate : nil,
            clinicNote: clinicNote.trimmingCharacters(in: .whitespacesAndNewlines),
            medicationIDs: Array(chosen.keys)
        )

        MedicationStore.add(
            prescription: prescription,
            refills: chosen.map { (medicationID: $0.key, quantity: $0.value) },
            at: visitDate,
            in: context
        )

        AppServices.shared.pushWatchSnapshot()

        // 다음 진료일이 바뀌었으니 진료 알림도 다시 깐다.
        Task {
            await ReminderPlanner.rescheduleAppointments(using: context)
            isSaving = false
            onSaved()
        }
    }
}

#Preview {
    NavigationStack {
        PrescriptionFormView {}
    }
    .environmentObject(ProStore())
    .modelContainer(for: JanjanSchema.allModels, inMemory: true)
}
