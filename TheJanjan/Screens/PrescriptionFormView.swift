import SwiftUI
import SwiftData
import JanjanCore

/// 진료 기록 (설계 03절 · 05절). 화면 이름은 "처방 기록" 이었는데
/// "이번 진료 내용을 기록할 수 있어야 할 것 같은데" 라는 말에 바꿨다
/// (2026-09-19) - 사용자는 이 일을 처방이 아니라 진료로 부른다. "지난 진료"
/// 화면과도 짝이 맞는다.
///
/// 이 화면 하나가 "다음 진료 D-" 와 "진료 전에 모자라는 약" 을 살린다.
/// 둘 다 진료일과 받아 온 개수를 알아야 계산할 수 있기 때문이다.
/// 여기서 들은 용량 변경은 적어 두는 데 그치지 않고 약에 바로 적용된다.
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
    /// 약 id → 진료일에 세어 둔 "받기 전 남아 있던 개수". 안 세면 여기 없다.
    /// 매 진료마다 남은 개수를 짚고 넘어가게 하는 손잡이다(사용자 결정 2026-09-16).
    @State private var leftovers: [UUID: Decimal] = [:]
    @State private var isSaving = false
    /// 사용자가 개수를 직접 고친 약. 제안값을 다시 덮어쓰지 않으려고 기억해 둔다.
    @State private var edited: Set<UUID> = []
    /// 이번 진료에서 처음 받은 약을 그 자리에서 등록하는 시트.
    @State private var isShowingNewMedication = false
    /// 이번 진료에서 용량이 바뀐 약. 손잡이를 켠 약만 여기 있다.
    @State private var doseEdits: [UUID: DoseEdit] = [:]

    /// 진료에서 들은 용량 변경 하나. 표기와 1회 개수를 따로 든다 —
    /// "10mg 에서 15mg" 과 "아침 1정에서 2정" 은 둘 다 "용량이 바뀌었다" 이고,
    /// 둘 중 하나만 바뀌는 날이 더 흔하다.
    private struct DoseEdit {
        var strengthText: String
        /// nil 이면 개수는 건드리지 않는다. 시간대마다 개수가 다른 약도 nil 이다.
        var perIntake: Decimal?
    }

    init(onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        let today = Date()
        _visitDate = State(initialValue: today)
        _nextVisitDate = State(
            initialValue: Calendar.current.date(byAdding: .day, value: 28, to: today) ?? today
        )
    }

    private var activeMedications: [Medication] {
        medicationRecords.map { $0.core.displayReady }.filter { $0.status == .active }
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
        .navigationTitle(t("진료 기록", "Log a visit"))
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
                    // 시간까지 받는다(사용자 결정 2026-09-16) - 진료 알림이 그 시각에 맞춰진다.
                    DatePicker(
                        t("다음 진료", "Next visit"),
                        selection: $nextVisitDate,
                        in: visitDate...,
                        displayedComponents: [.date, .hourAndMinute]
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

                Text(t("이름을 누르면 이번 처방에 넣거나 빼요.", "Tap a name to add it to or remove it from this prescription."))
                    .janjanBody(12)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(activeMedications) { medication in
                    medicationRow(medication)
                }

                // 이번 진료에서 처음 받은 약은 여기서 바로 등록한다 - 폼을 닫고
                // 약 탭으로 돌아갔다 오게 하지 않는다(사용자 결정 2026-09-16).
                WhitePillButton(title: t("여기 없는 약 등록", "Register a new medication"), systemImage: "plus") {
                    isShowingNewMedication = true
                }
            }
        }
        .sheet(isPresented: $isShowingNewMedication) {
            NavigationStack {
                MedicationFormView { isShowingNewMedication = false }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(t("닫기", "Close")) { isShowingNewMedication = false }
                                .foregroundStyle(Color.ink)
                        }
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
                // VoiceOver 가 가린 이름을 소리 내어 읽으면 가림이 뚫린다 -
                // 눈에 보이는 손잡이(togglePill)와 같은 규칙으로 용도줄로 부른다.
                let spokenName = masksNames
                    ? (medication.purposeLine.isEmpty ? t("가려진 약", "hidden medication") : medication.purposeLine)
                    : medication.name

                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                    Text(t("받아 온 개수", "Pills picked up"))
                        .janjanBody(11)
                        .foregroundStyle(Color.muted)
                    CountStepper(
                        text: t("\(DecimalQuantity.display(quantity))정", pillsEn(quantity)),
                        decreaseLabelKo: t("\(spokenName) 개수 줄이기", "Decrease \(spokenName) count"),
                        increaseLabelKo: t("\(spokenName) 개수 늘리기", "Increase \(spokenName) count"),
                        onDecrease: { adjust(medication, by: -1) },
                        onIncrease: { adjust(medication, by: 1) }
                    )
                }

                if let leftover = leftovers[medication.id] {
                    VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                        Text(t("받기 전 남아 있던 개수", "Pills left before this refill"))
                            .janjanBody(11)
                            .foregroundStyle(Color.muted)
                        CountStepper(
                            text: t("\(DecimalQuantity.display(leftover))정", pillsEn(leftover)),
                            decreaseLabelKo: t("\(spokenName) 남은 개수 줄이기", "Decrease \(spokenName) leftover count"),
                            increaseLabelKo: t("\(spokenName) 남은 개수 늘리기", "Increase \(spokenName) leftover count"),
                            onDecrease: { adjustLeftover(medication, by: -1) },
                            onIncrease: { adjustLeftover(medication, by: 1) }
                        )
                    }
                } else {
                    // 매 진료마다 남은 개수를 짚고 가면 재고가 실제와 다시 맞는다.
                    // 강요는 아니다 - 안 세면 그냥 보충만 더해진다.
                    WhitePillButton(title: t("남아 있던 약도 세어 두기", "Also count what was left"), systemImage: "number") {
                        leftovers[medication.id] = 0
                    }
                }

                doseChangeSection(medication)
            }
        }
        .padding(.vertical, CGFloat(JanjanSpacing.xxs))
    }

    /// 진료에서 용량이 바뀌었을 때. **적어 두기만 하지 않고 그 자리에서 적용한다**
    /// (사용자 요청 2026-09-19). 적어 두기만 하면 재고와 소진 예측이 옛 개수로
    /// 계속 세고, 사용자는 앱이 틀린 숫자를 말한다고 느낀다.
    @ViewBuilder
    private func doseChangeSection(_ medication: Medication) -> some View {
        if let edit = doseEdits[medication.id] {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                JanjanField(
                    label: t("바뀐 용량", "New dose"),
                    placeholder: medication.strengthText.isEmpty
                        ? t("예: 15mg", "e.g. 15mg")
                        : medication.strengthText,
                    text: Binding(
                        get: { doseEdits[medication.id]?.strengthText ?? "" },
                        set: { doseEdits[medication.id]?.strengthText = $0 }
                    )
                )

                if let perIntake = edit.perIntake {
                    VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                        Text(t("한 번에 먹는 개수", "Pills per dose"))
                            .janjanBody(11)
                            .foregroundStyle(Color.muted)
                        CountStepper(
                            text: t("\(DecimalQuantity.display(perIntake))정", pillsEn(perIntake)),
                            decreaseLabelKo: t("1회 개수 줄이기", "Decrease pills per dose"),
                            increaseLabelKo: t("1회 개수 늘리기", "Increase pills per dose"),
                            onDecrease: { adjustPerIntake(medication, by: -1) },
                            onIncrease: { adjustPerIntake(medication, by: 1) }
                        )
                    }
                } else if hasMixedDoses(medication) {
                    // 시간대마다 개수가 다른 약에 한 숫자를 밀어 넣으면 아침 2정
                    // 저녁 1정이 조용히 2정 2정이 된다. 그 경우는 막고 보낸다.
                    Text(t(
                        "시간대마다 개수가 달라요. 개수는 약 화면의 '고치기' 에서 바꿔 주세요.",
                        "The count differs by time slot. Change it with 'Edit' on the medication screen."
                    ))
                        .janjanBody(12)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(t(
                    "저장하면 이 약의 용량이 바로 바뀌고, 용량 변경 이력에도 남아요.",
                    "Saving changes this medication's dose right away and records it in the dose change history."
                ))
                    .janjanBody(11)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)

                WhitePillButton(title: t("용량 변경 취소", "Cancel dose change"), systemImage: "arrow.uturn.backward") {
                    doseEdits[medication.id] = nil
                    refreshSuggestions()
                }
            }
            .padding(.top, CGFloat(JanjanSpacing.xxs))
        } else {
            WhitePillButton(title: t("용량이 바뀌었어요", "The dose changed"), systemImage: "arrow.left.arrow.right") {
                doseEdits[medication.id] = DoseEdit(
                    strengthText: medication.strengthText,
                    perIntake: commonDose(medication)
                )
            }
            .padding(.top, CGFloat(JanjanSpacing.xxs))
        }
    }

    /// 이 알약은 눌러서 이번 처방에 포함시키는 손잡이다 - 이름 자리에 따로 탭을
    /// 두면 손잡이 전체의 탭(선택 · 해제)과 겹친다. 그래서 `MaskedNameText` 대신
    /// 가려졌을 때는 점 표기만 보여 주고, 다시 눌러 보이게 하는 동작은 두지 않는다
    /// (약 목록 행과 같은 판단 - `MedicationsView.medicationNameText` 참고).
    @ViewBuilder
    private func togglePill(for medication: Medication) -> some View {
        if masksNames {
            // 여러 약이 전부 점이면 어느 것을 고르는지 알 수 없다. 목록 행과 같은
            // 규칙으로 용도 한 줄이 있으면 그것으로 부르고, 그것도 없으면
            // 용량 표기를 붙인다 - "10mg" 은 약 이름이 아니라서 가림이 뚫리지
            // 않으면서, 점 두 개를 서로 다른 것으로 만들어 준다(QA 2026-09-19).
            TogglePill(
                text: maskedLabel(for: medication),
                isOn: refills[medication.id] != nil
            ) {
                toggle(medication)
            }
            .accessibilityLabel(Text(maskedSpokenLabel(for: medication)))
        } else {
            TogglePill(
                text: medication.displayTitle,
                isOn: refills[medication.id] != nil
            ) {
                toggle(medication)
            }
        }
    }

    /// 이름을 가린 약을 화면에서 부르는 말. 용도 한 줄 → 용량 표기 → 점 차례다.
    private func maskedLabel(for medication: Medication) -> String {
        if !medication.purposeLine.isEmpty { return medication.purposeLine }
        if !medication.strengthText.isEmpty {
            return "\(MaskedNameText.maskGlyph) \(medication.strengthText)"
        }
        return MaskedNameText.maskGlyph
    }

    /// VoiceOver 가 읽을 말. 가린 이름은 절대 읽지 않는다 - 소리로 뚫리면
    /// 가림이 아니다.
    private func maskedSpokenLabel(for medication: Medication) -> String {
        if !medication.purposeLine.isEmpty { return medication.purposeLine }
        if !medication.strengthText.isEmpty {
            return t("가려진 약, \(medication.strengthText)", "Hidden medication, \(medication.strengthText)")
        }
        return t("가려진 약 이름", "Hidden medication name")
    }

    private var noteCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                JanjanField(
                    label: t("진료 메모 (선택)", "Visit note (optional)"),
                    placeholder: t("예: 용량 절반으로", "e.g. Cut the dose in half"),
                    text: $clinicNote
                )
                Text(t("진료 시 들었던 내용을 메모로 남겨요.", "Note down what you heard at the visit."))
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
            leftovers[medication.id] = nil
            // 이번 처방에서 뺀 약의 용량 변경까지 들고 있으면, 화면에 보이지도
            // 않는 것이 저장될 때 적용된다.
            doseEdits[medication.id] = nil
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

    private func adjustLeftover(_ medication: Medication, by delta: Decimal) {
        guard let current = leftovers[medication.id] else { return }
        leftovers[medication.id] = max(current + delta, 0)
    }

    private func mySchedules(_ medication: Medication) -> [Schedule] {
        schedules.filter { $0.medicationID == medication.id }
    }

    /// 모든 시간대가 같은 개수일 때 그 값. 시간대가 없거나 서로 다르면 nil.
    private func commonDose(_ medication: Medication) -> Decimal? {
        let doses = Set(mySchedules(medication).map(\.dosePerIntake))
        return doses.count == 1 ? doses.first : nil
    }

    private func hasMixedDoses(_ medication: Medication) -> Bool {
        Set(mySchedules(medication).map(\.dosePerIntake)).count > 1
    }

    private func adjustPerIntake(_ medication: Medication, by direction: Int) {
        guard var edit = doseEdits[medication.id], let current = edit.perIntake else { return }
        // 쪼갤 수 없는 제형은 1정 단위로만 센다(등록 폼과 같은 규칙).
        let step: Decimal = medication.form.isSplittable ? DecimalQuantity.step * 2 : 1
        let next = DecimalQuantity.snapToQuarter(current + (direction > 0 ? step : -step))
        edit.perIntake = max(next, step)
        doseEdits[medication.id] = edit
        // 하루치가 바뀌었으니 받아 온 개수 제안도 새 개수를 따라가야 말이 맞는다.
        refreshSuggestions()
    }

    /// 처방일수 × 하루 예정 개수. 스케줄이 없으면 하루 1정으로 본다.
    ///
    /// 이번 진료에서 1회 개수를 바꿨다면 **새 개수로 센다.** 저장한 뒤의 하루치는
    /// 이미 새 개수이므로, 제안만 옛 개수를 따르면 받아 온 양이 늘 어긋난다.
    private func suggestedQuantity(for medication: Medication) -> Decimal {
        var mine = mySchedules(medication)
        if let pending = doseEdits[medication.id]?.perIntake {
            mine = mine.map { schedule in
                var changed = schedule
                changed.dosePerIntake = pending
                return changed
            }
        }
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

        // 남은 개수는 이번 처방에 포함한 약의 것만 저장한다 - 세다가 약을 뺐으면
        // 그 숫자는 버린다.
        let counted = leftovers.filter { refills[$0.key] != nil }

        MedicationStore.add(
            prescription: prescription,
            refills: chosen.map { (medicationID: $0.key, quantity: $0.value) },
            leftovers: counted.map { (medicationID: $0.key, count: $0.value) },
            at: visitDate,
            in: context
        )

        applyDoseChanges()

        AppServices.shared.pushWatchSnapshot()

        // 다음 진료일이 바뀌었고, 1회 개수가 바뀐 약이 있으면 알림에 뜨는
        // 개수도 달라진다. 진료 알림과 복약 알림을 함께 다시 깐다.
        Task {
            await ReminderPlanner.rescheduleAppointments(using: context)
            await ReminderPlanner.reschedule(using: context)
            isSaving = false
            onSaved()
        }
    }

    /// 진료에서 들은 용량 변경을 약에 실제로 옮긴다.
    ///
    /// 바뀐 것이 없는 줄은 건너뛴다 - 손잡이만 켰다가 아무것도 고치지 않은
    /// 경우에 "10mg → 10mg" 이 이력에 쌓이면 안 된다. 날짜는 오늘이 아니라
    /// **진료일**이다. 전후 비교가 그 날을 축으로 그린다.
    private func applyDoseChanges() {
        for (medicationID, edit) in doseEdits {
            guard let medication = activeMedications.first(where: { $0.id == medicationID }) else { continue }

            let newText = edit.strengthText.trimmingCharacters(in: .whitespacesAndNewlines)
            let textChanged = !newText.isEmpty && newText != medication.strengthText
            let doseChanged = edit.perIntake != nil && edit.perIntake != commonDose(medication)
            guard textChanged || doseChanged else { continue }

            MedicationStore.applyDoseChange(
                medicationID: medicationID,
                newStrengthText: textChanged ? newText : nil,
                newDosePerIntake: doseChanged ? edit.perIntake : nil,
                changedAt: visitDate,
                note: clinicNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : clinicNote.trimmingCharacters(in: .whitespacesAndNewlines),
                in: context
            )
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
