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

    @Query(sort: \MedicationRecord.createdAt) private var medicationRecords: [MedicationRecord]
    @Query private var scheduleRecords: [ScheduleRecord]

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

                BlackPillButton(title: "저장", isBusy: isSaving, isEnabled: canSave) {
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
        .navigationTitle("처방 기록")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 카드

    private var visitCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
                DatePicker(
                    "진료 받은 날",
                    selection: $visitDate,
                    displayedComponents: .date
                )
                .font(JanjanFont.body(15))
                .tint(Color.ink)
                .onChange(of: visitDate) { _, _ in refreshSuggestions() }

                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                    Text("며칠치를 받았어요?")
                        .font(JanjanFont.body(12, weight: .medium))
                        .foregroundStyle(Color.muted)
                    CountStepper(
                        text: "\(daysSupplied)일치",
                        decreaseLabelKo: "처방 일수 줄이기",
                        increaseLabelKo: "처방 일수 늘리기",
                        onDecrease: { changeDays(by: -7) },
                        onIncrease: { changeDays(by: 7) }
                    )
                }

                Toggle("다음 진료일이 정해졌어요", isOn: $hasNextVisit)
                    .font(JanjanFont.body(15))
                    .tint(Color.ink)

                if hasNextVisit {
                    DatePicker(
                        "다음 진료",
                        selection: $nextVisitDate,
                        in: visitDate...,
                        displayedComponents: .date
                    )
                    .font(JanjanFont.body(15))
                    .tint(Color.ink)
                }
            }
        }
    }

    private var emptyCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text("등록된 약이 없어요")
                    .font(JanjanFont.display(20))
                    .foregroundStyle(Color.ink)
                Text("약을 먼저 등록하면 여기서 받아 온 개수를 함께 적을 수 있어요. 진료일만 먼저 남겨도 괜찮아요.")
                    .font(JanjanFont.body(13))
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var medicationCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("이번에 받아 온 약")
                    .font(JanjanFont.body(12, weight: .medium))
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
                TogglePill(
                    text: medication.displayTitle,
                    isOn: refills[medication.id] != nil
                ) {
                    toggle(medication)
                }
                Spacer(minLength: 0)
            }

            if let quantity = refills[medication.id] {
                CountStepper(
                    text: "\(DecimalQuantity.display(quantity))정",
                    decreaseLabelKo: "\(medication.name) 개수 줄이기",
                    increaseLabelKo: "\(medication.name) 개수 늘리기",
                    onDecrease: { adjust(medication, by: -1) },
                    onIncrease: { adjust(medication, by: 1) }
                )
            }
        }
        .padding(.vertical, CGFloat(JanjanSpacing.xxs))
    }

    private var noteCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                JanjanField(
                    label: "진료 메모 (선택)",
                    placeholder: "예: 용량 절반으로",
                    text: $clinicNote
                )
                Text("들은 말을 그대로 적어 두면 다음 진료에서 되짚기 쉬워요.")
                    .font(JanjanFont.body(12))
                    .foregroundStyle(Color.muted)
            }
        }
    }

    // MARK: - 규칙

    /// 진료일만 있어도 저장된다. 약을 아직 안 넣었어도 "다음 진료 D-" 는 살아난다.
    private var canSave: Bool { !isSaving }

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
        isSaving = false
        onSaved()
    }
}

#Preview {
    NavigationStack {
        PrescriptionFormView {}
    }
    .modelContainer(for: JanjanSchema.allModels, inMemory: true)
}
