import SwiftUI
import SwiftData
import JanjanCore

/// 약 등록 폼 (설계 03절). **고치기도 같은 화면이 맡는다**(2026-09-19).
///
/// 필수는 이름 하나뿐이다. 나머지는 비워 둬도 저장되고 나중에 채울 수 있다 —
/// 등록 화면에서 막히면 앱을 아예 쓰지 않게 되기 때문이다.
///
/// 시스템 `Form` 을 쓰지 않고 흰 카드로 짠다. 회색 그룹 목록은 이 앱의 시각 언어가 아니다.
///
/// 등록한 뒤에는 이름도 1회 개수도 먹는 때도 고칠 수 없었다(사용자 발견
/// 2026-09-19 "약 용량 바뀐 건 어디서 바꿔?"). 정신과 처방은 용량이 자주
/// 바뀌는데, 고칠 길이 없으면 약을 지우고 다시 넣는 수밖에 없고 그러면 그
/// 약의 지난 복용 기록이 통째로 사라진다. 같은 폼을 수정 모드로 연다 —
/// 두 벌로 나누면 한쪽만 고쳐지는 날이 반드시 온다.
struct MedicationFormView: View {

    /// 고칠 약을 열 때 넘기는 지금 값.
    struct Existing {
        let medication: Medication
        let schedules: [Schedule]
    }

    /// 저장이 끝난 뒤 바깥(약 추가 시트)까지 닫아 주는 손잡이.
    let onSaved: () -> Void

    /// 고치는 중인 약. nil 이면 새로 만드는 것이다.
    private let editingID: UUID?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var strength: String
    @State private var purpose = ""
    @State private var form: Medication.Form = .tablet
    @State private var kind: Medication.Kind = .scheduled
    /// 기본은 아무 요일도 고르지 않은 상태 - 직접 눌러 고른다
    /// (사용자 요청 2026-09-19. 전에는 매일이 기본이라 지나치기 쉬웠다).
    @State private var weekdays: Set<Weekday> = []
    @State private var stockText = ""
    @State private var drafts: [SlotDraft] = SlotDraft.presets()
    @State private var isSaving = false
    /// 알림 권한을 묻는 화면. 시간이 있는 약을 저장한 직후에만 올라온다.
    @State private var isAskingNotification = false


    private var lang: JanjanLanguage { .current }

    /// - Parameter prefill: 약봉투 스캔이 읽어 온 값. 채워만 두고 사용자가 고칠 수 있다 —
    ///   잘못 읽은 이름이 확인 없이 저장되면 그 뒤 기록이 전부 그 위에 쌓인다.
    init(prefill: PharmacyLabelParser.Candidate? = nil, onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        self.editingID = nil
        _name = State(initialValue: prefill?.name ?? "")
        _strength = State(initialValue: prefill?.strengthText ?? "")
    }

    /// 등록한 약을 고치러 들어오는 길. 저장하면 스스로 닫고 상세 화면으로 돌아간다.
    init(existing: Existing) {
        self.onSaved = {}
        self.editingID = existing.medication.id
        _name = State(initialValue: existing.medication.name)
        _strength = State(initialValue: existing.medication.strengthText)
        _purpose = State(initialValue: existing.medication.purposeLine)
        _form = State(initialValue: existing.medication.form)
        _kind = State(initialValue: existing.medication.kind)
        // 요일은 줄마다 따로 저장되지만 화면에서는 약 하나에 한 벌이다.
        // 지금까지 만들어진 약은 줄들이 같은 요일을 갖고 있으므로 첫 줄을 쓴다.
        //
        // 시간대가 없는 약(필요시)을 고치러 열면 고를 요일이 없다. 그때
        // "매일" 로 채워 두면 새 등록에서 일부러 없앴던 그 기본값이 —
        // 지나치기 쉬워서 없앴다 — 이 문을 통해 되살아난다(QA 2026-09-19).
        // 새 등록과 같이 빈 채로 시작한다.
        _weekdays = State(initialValue: existing.schedules.first?.weekdays ?? [])
        _drafts = State(initialValue: SlotDraft.from(existing.schedules))
    }

    private var isEditing: Bool { editingID != nil }

    /// 시간대 한 줄의 초안. 켜진 것만 스케줄이 된다.
    ///
    /// id 는 UUID 다. 예전에는 slot.storageKey 를 썼는데, 직접 넣은 시간대는
    /// 시각을 옮기는 순간 키가 바뀌어 줄의 정체성이 흔들린다.
    private struct SlotDraft: Identifiable {
        let id = UUID()
        /// 아침·점심·저녁·취침이면 그 값. 직접 추가한 줄이면 nil — 시각이 곧 정체성이다.
        let preset: DoseSlot?
        var isOn: Bool
        /// DatePicker 가 Date 만 다뤄서 시·분을 Date 에 얹어 들고 있는다.
        var time: Date
        var dose: Decimal
        /// 고치기로 열 때 이 줄이 갖고 있던 시작일. 그대로 돌려준다 -
        /// 고치기 한 번에 모든 줄의 시작일을 오늘로 바꾸면 지난 복약률이
        /// 통째로 다시 계산된다.
        var originalStartDate: Date?
        /// 고치기로 열 때 이 줄이 갖고 있던 저장 키. 새로 만드는 줄이면 nil.
        ///
        /// 직접 넣은 시간대는 **시각이 곧 키**다("custom-14:30"). 고치기에서
        /// 14:30 을 15:00 으로 옮기면 키가 바뀌고, 그 시간대에 이미 답해 둔
        /// 지난 날들이 새 키로는 안 잡혀 "기록 없이 지나간 시간대" 로 되살아난다
        /// (QA 2026-09-19). 옮기기 전 키를 들고 있다가 지난 기록의 키도 함께
        /// 옮겨 준다.
        var originalSlotKey: String?

        var timeOfDay: TimeOfDay {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        }

        /// 저장에 쓰는 시간대. 직접 추가한 줄은 고른 시각 그대로 custom 이 된다.
        var slot: DoseSlot { preset ?? .custom(timeOfDay) }

        static func presets() -> [SlotDraft] {
            DoseSlot.presets.map { slot in
                SlotDraft(
                    preset: slot,
                    isOn: false,
                    time: slot.defaultTime.date(on: Date()),
                    dose: 1
                )
            }
        }

        /// 하루 네 번으로 모자랄 때 더하는 줄. 더했다는 것이 곧 쓰겠다는 뜻이라 켜진 채 온다.
        static func custom() -> SlotDraft {
            SlotDraft(preset: nil, isOn: true, time: Date(), dose: 1)
        }

        /// 저장된 스케줄을 폼의 줄로 되돌린다.
        ///
        /// 아침·점심·저녁·취침은 늘 같은 자리에 있어야 하므로 프리셋 네 줄을
        /// 먼저 깔고 그 위에 켠다. 직접 넣었던 시각은 뒤에 이어 붙인다 -
        /// 없어지면 사용자가 만든 시간대가 고치기 한 번에 조용히 사라진다.
        static func from(_ schedules: [Schedule], on day: Date = Date()) -> [SlotDraft] {
            var rows = presets()
            var extras: [SlotDraft] = []

            for schedule in schedules.sorted(by: { $0.timeOfDay < $1.timeOfDay }) {
                let time = schedule.timeOfDay.date(on: day)
                if let index = rows.firstIndex(where: { $0.preset == schedule.slot }) {
                    rows[index].isOn = true
                    rows[index].time = time
                    rows[index].dose = schedule.dosePerIntake
                    rows[index].originalStartDate = schedule.startDate
                    rows[index].originalSlotKey = schedule.slot.storageKey
                } else {
                    extras.append(SlotDraft(
                        preset: nil,
                        isOn: true,
                        time: time,
                        dose: schedule.dosePerIntake,
                        originalStartDate: schedule.startDate,
                        originalSlotKey: schedule.slot.storageKey
                    ))
                }
            }
            return rows + extras
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: CGFloat(JanjanSpacing.s)) {
                identityCard
                kindCard
                if kind == .scheduled {
                    slotCard
                    weekdayCard
                }
                // 재고는 "세어 본 사건" 이 쌓여 만들어지는 값이라 고치기에서
                // 숫자 하나로 덮으면 기준점이 끊긴다. 다시 세는 일은 상세
                // 화면의 "다시 세기" 가 맡는다.
                if !isEditing {
                    stockCard
                }
                if isEditing {
                    editingNoteCard
                }

                BlackPillButton(
                    title: isEditing ? t("고치기", "Save changes") : t("저장", "Save"),
                    isBusy: isSaving,
                    isEnabled: canSave
                ) {
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
        .navigationTitle(isEditing ? t("약 고치기", "Edit medication") : t("직접 입력", "Enter manually"))
        .navigationBarTitleDisplayMode(.inline)

        .fullScreenCover(isPresented: $isAskingNotification) {
            NotificationPermissionView {
                NotificationPermissionGate.hasAsked = true
                // 권한을 받은 뒤에 다시 깔아야 방금 등록한 약의 알림이 실제로 예약된다.
                Task {
                    await ReminderPlanner.reschedule(using: context)
                    onSaved()
                }
            }
        }
    }

    // MARK: - 카드

    private var identityCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
                JanjanField(label: t("이름", "Name"), placeholder: t("예: 에스시탈로프람", "e.g. Escitalopram"), text: $name)
                JanjanField(label: t("용량", "Dose"), placeholder: t("예: 10mg", "e.g. 10mg"), text: $strength)
                JanjanField(
                    label: t("용도 한 줄 (선택)", "What it's for (optional)"),
                    placeholder: t("예: 잠들기 쉽게", "e.g. To help me sleep"),
                    text: $purpose
                )
            }
        }
    }

    private var kindCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(t("어떻게 먹는 약인가요", "How do you take it"))
                    .janjanBody(12, weight: .medium)
                    .foregroundStyle(Color.muted)

                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    ForEach(Medication.Kind.allCases, id: \.self) { option in
                        TogglePill(text: option.label(lang), isOn: kind == option) {
                            kind = option
                        }
                    }
                }

                Text(t("제형", "Form"))
                    .janjanBody(12, weight: .medium)
                    .foregroundStyle(Color.muted)
                    .padding(.top, CGFloat(JanjanSpacing.xs))

                Picker(t("제형", "Form"), selection: $form) {
                    ForEach(Medication.Form.allCases, id: \.self) { option in
                        Text(option.label(lang)).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.ink)

                if !form.isSplittable {
                    Text(t("이 제형은 쪼개 먹지 않는 것으로 보고 개수를 1정 단위로만 셉니다.", "This form isn't split, so counts are tracked in whole pills only."))
                        .janjanBody(12)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var slotCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(t("언제 먹나요", "When do you take it"))
                    .janjanBody(12, weight: .medium)
                    .foregroundStyle(Color.muted)

                ForEach($drafts) { $draft in
                    slotRow($draft)
                }

                // 요일 카드와 같은 규칙 - 저장이 막히는 이유는 막는 자리에서 말한다.
                // 여기만 안내가 없어서 "요일은 골랐는데 왜 저장이 안 되지" 가 됐다
                // (QA 2026-09-19).
                if !drafts.contains(where: \.isOn) {
                    Text(t(
                        "시간대를 하나는 켜 주세요. 켠 시간대에만 알림이 가요.",
                        "Turn on at least one time slot. Reminders only go out for the slots you turn on."
                    ))
                        .janjanBody(12)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 정신과 처방은 하루 네 번을 넘기도 한다(분복 등). 모자라면 더 넣는다.
                WhitePillButton(title: t("시간대 추가", "Add a time"), systemImage: "plus") {
                    drafts.append(.custom())
                }
            }
        }
    }

    private func slotRow(_ draft: Binding<SlotDraft>) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
            HStack {
                if let preset = draft.wrappedValue.preset {
                    TogglePill(text: preset.label(lang), isOn: draft.wrappedValue.isOn) {
                        draft.wrappedValue.isOn.toggle()
                    }
                } else {
                    // 직접 넣은 줄에는 켜고 끄기가 없다. 안 쓸 거면 빼면 된다.
                    Button {
                        drafts.removeAll { $0.id == draft.wrappedValue.id }
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(Color.ink2)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(t("이 시간대 빼기", "Remove this time slot")))
                }
                Spacer(minLength: CGFloat(JanjanSpacing.xs))
                if draft.wrappedValue.isOn {
                    DatePicker(
                        "",
                        selection: draft.time,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .accessibilityLabel(Text(t(
                        "\(draft.wrappedValue.slot.labelKo) 시각",
                        "\(draft.wrappedValue.slot.label(lang)) time"
                    )))
                }
            }

            if draft.wrappedValue.isOn {
                doseStepper(draft)
            }
        }
        .padding(.vertical, CGFloat(JanjanSpacing.xxs))
    }

    private func doseStepper(_ draft: Binding<SlotDraft>) -> some View {
        CountStepper(
            text: t("1회 \(DecimalQuantity.display(draft.wrappedValue.dose))정", "\(pillsEn(draft.wrappedValue.dose)) per dose"),
            decreaseLabelKo: t("개수 줄이기", "Decrease count"),
            increaseLabelKo: t("개수 늘리기", "Increase count"),
            onDecrease: { adjust(draft, by: -doseStep) },
            onIncrease: { adjust(draft, by: doseStep) }
        )
    }

    private var weekdayCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                HStack {
                    Text(t("무슨 요일에", "On which days"))
                        .janjanBody(12, weight: .medium)
                        .foregroundStyle(Color.muted)
                    Spacer(minLength: 0)
                    // 매일 먹는 약이 대부분이라 한 번에 켜는 손잡이를 둔다.
                    // 다 켜진 상태에서 다시 누르면 전부 꺼진다 - 같은 자리가 되돌리기다.
                    TogglePill(
                        text: t("모든 요일", "Every day"),
                        isOn: weekdays == Weekday.everyday
                    ) {
                        weekdays = weekdays == Weekday.everyday ? [] : Weekday.everyday
                    }
                }

                // 일곱 개가 화면 폭을 고르게 나눠 가진다. 최소 폭 40 을 그대로
                // 두면 일곱 개가 472pt 라 아이폰 어느 기기에도 들어가지 않는다.
                HStack(spacing: CGFloat(JanjanSpacing.xxs)) {
                    ForEach(Weekday.displayOrderKo, id: \.self) { day in
                        TogglePill(
                            text: day.label(lang),
                            isOn: weekdays.contains(day),
                            minWidth: 0,
                            fillsRow: true
                        ) {
                            toggle(day)
                        }
                    }
                }

                if weekdays.isEmpty {
                    Text(t("하루는 골라 주세요. 고른 요일에만 일정이 만들어져요.", "Pick at least one day. Only the days you choose get a schedule."))
                        .janjanBody(12)
                        .foregroundStyle(Color.muted)
                }
            }
        }
    }

    /// 고치기에서만 보이는 한 줄. 무엇이 남고 무엇이 바뀌는지 미리 말한다 -
    /// 지난 기록이 지워질까 봐 손을 못 대는 것이 제일 나쁘다.
    private var editingNoteCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                Text(t(
                    "지난 복용 기록과 남은 개수는 그대로 남아요.",
                    "Your past doses and pills on hand stay as they are."
                ))
                    .janjanBody(13)
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(t(
                    "먹는 때를 바꾸면 앞으로의 알림과 오늘 화면이 새 시각을 따라요. 남은 개수를 다시 세는 건 약 화면의 '다시 세기' 에서 해요.",
                    "Changing the times moves future reminders and the Today screen. To recount your pills, use 'Count again' on the medication screen."
                ))
                    .janjanBody(12)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var stockCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                JanjanField(
                    label: t("지금 남은 개수 (선택)", "Pills on hand (optional)"),
                    placeholder: t("예: 28", "e.g. 28"),
                    keyboard: .decimalPad,
                    text: $stockText
                )
                Text(t("세어 본 개수를 적으면 이 시점이 기준이 돼요. 비워 두면 재고를 세지 않아요.", "Enter the count you've checked and this moment becomes the baseline. Leave it blank to skip tracking stock."))
                    .janjanBody(12)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 규칙

    /// 쪼갤 수 없는 제형은 1정 단위로만 센다(설계 03절의 제형 규칙).
    private var doseStep: Decimal {
        form.isSplittable ? DecimalQuantity.step * 2 : 1
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // 필요시 약은 시간대가 없어도 된다 — 그게 필요시 약의 정의다.
        guard kind == .scheduled else { return true }
        // 요일을 하나도 안 고르면 알림도 안 가고, 오늘 화면에도 안 뜨고,
        // 재고도 안 줄어든다. 저장은 되는데 아무 일도 일어나지 않는 약이 생긴다.
        return drafts.contains { $0.isOn } && !weekdays.isEmpty
    }

    private func adjust(_ draft: Binding<SlotDraft>, by delta: Decimal) {
        let next = DecimalQuantity.snapToQuarter(draft.wrappedValue.dose + delta)
        draft.wrappedValue.dose = max(next, doseStep)
    }

    private func toggle(_ day: Weekday) {
        if weekdays.contains(day) {
            weekdays.remove(day)
        } else {
            weekdays.insert(day)
        }
    }

    /// "1.5", "1,5" 둘 다 받는다. 숫자가 아니면 재고를 적지 않은 것으로 본다.
    private var initialStock: Decimal? {
        let trimmed = stockText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty, let value = Decimal(string: trimmed), value >= 0 else { return nil }
        return DecimalQuantity.snapToQuarter(value)
    }

    // MARK: - 저장

    /// 켜 둔 줄만 스케줄이 된다. 필요시 약은 시간대를 갖지 않는다.
    ///
    /// 고치면서 **새로 켠 시간대에는 오늘을 시작일로 박는다**(QA 2026-09-19).
    /// 아침만 먹던 약에 저녁을 더했을 때, 시작일이 없으면 지난 한 달의 저녁이
    /// 전부 "빠트린 것" 으로 되살아난다 - 그 시간대는 그때 존재하지 않았다.
    /// 원래 있던 줄은 갖고 있던 시작일을 그대로 돌려준다.
    private func makeSchedules(for medicationID: UUID) -> [Schedule] {
        (kind == .scheduled ? drafts.filter(\.isOn) : []).map { draft in
            Schedule(
                medicationID: medicationID,
                slot: draft.slot,
                timeOfDay: draft.timeOfDay,
                weekdays: weekdays,
                dosePerIntake: draft.dose,
                startDate: startDate(for: draft)
            )
        }
    }

    private func startDate(for draft: SlotDraft) -> Date? {
        if let original = draft.originalStartDate { return original }
        // 원래 있던 줄(키를 갖고 열린 줄)은 시작일이 없던 그대로 둔다 -
        // 약의 등록 시각이 이미 경계를 잡아 준다.
        if draft.originalSlotKey != nil { return nil }
        // 새로 만드는 약의 줄도 마찬가지다. 고치면서 더한 줄만 오늘부터다.
        guard isEditing else { return nil }
        return Calendar.current.startOfDay(for: Date())
    }

    /// 고치면서 저장 키가 옮겨진 시간대. 지난 기록의 키도 같이 옮겨야 한다.
    /// 프리셋은 시각을 옮겨도 키가 그대로라 여기 들어올 일이 없다.
    private var slotKeyRenames: [String: String] {
        var renames: [String: String] = [:]
        guard kind == .scheduled else { return renames }
        for draft in drafts where draft.isOn {
            guard let original = draft.originalSlotKey else { continue }
            let now = draft.slot.storageKey
            if original != now { renames[original] = now }
        }
        return renames
    }

    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true

        if let editingID {
            saveEdit(to: editingID)
            return
        }

        let medication = Medication(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            strengthText: strength.trimmingCharacters(in: .whitespacesAndNewlines),
            form: form,
            kind: kind,
            purposeLine: purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let schedules = makeSchedules(for: medication.id)

        MedicationStore.add(
            MedicationStore.Draft(
                medication: medication,
                schedules: schedules,
                initialStock: initialStock
            ),
            in: context
        )

        Task {
            await ReminderPlanner.reschedule(using: context)
            AppServices.shared.pushWatchSnapshot()
            isSaving = false

            // 시간이 있는 약을 처음 넣었다면 여기서 알림 권한을 묻는다.
            // 이 자리가 아니면 물어볼 자리가 없다 — 알림이 처음으로 뜻을 갖는 순간이다.
            if !schedules.isEmpty, await NotificationPermissionGate.shouldAsk() {
                isAskingNotification = true
                return
            }

            // 닫는 일은 바깥에 맡긴다. 폼이 스스로 pop 하면서 시트까지 닫으면
            // 화면이 두 번 사라지며 애니메이션이 엉킨다.
            onSaved()
        }
    }

    /// 고치기는 밀려 올라온 화면이라 스스로 닫고 상세로 돌아간다.
    /// 알림 권한은 묻지 않는다 - 이미 쓰고 있던 약이라 물을 자리가 아니다.
    private func saveEdit(to medicationID: UUID) {
        MedicationStore.update(
            MedicationStore.Edit(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                strengthText: strength.trimmingCharacters(in: .whitespacesAndNewlines),
                form: form,
                kind: kind,
                purposeLine: purpose.trimmingCharacters(in: .whitespacesAndNewlines),
                schedules: makeSchedules(for: medicationID),
                slotKeyRenames: slotKeyRenames
            ),
            for: medicationID,
            in: context
        )

        Task {
            await ReminderPlanner.reschedule(using: context)
            AppServices.shared.pushWatchSnapshot()
            isSaving = false
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        MedicationFormView {}
    }
    .modelContainer(for: JanjanSchema.allModels, inMemory: true)
}
