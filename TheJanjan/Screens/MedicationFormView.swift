import SwiftUI
import SwiftData
import JanjanCore

/// 약 등록 폼 (설계 03절).
///
/// 필수는 이름 하나뿐이다. 나머지는 비워 둬도 저장되고 나중에 채울 수 있다 —
/// 등록 화면에서 막히면 앱을 아예 쓰지 않게 되기 때문이다.
///
/// 시스템 `Form` 을 쓰지 않고 흰 카드로 짠다. 회색 그룹 목록은 이 앱의 시각 언어가 아니다.
struct MedicationFormView: View {

    /// 저장이 끝난 뒤 바깥(약 추가 시트)까지 닫아 주는 손잡이.
    let onSaved: () -> Void

    @Environment(\.modelContext) private var context

    @State private var name: String
    @State private var strength: String
    @State private var purpose = ""
    @State private var form: Medication.Form = .tablet
    @State private var kind: Medication.Kind = .scheduled
    @State private var weekdays: Set<Weekday> = Weekday.everyday
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
        _name = State(initialValue: prefill?.name ?? "")
        _strength = State(initialValue: prefill?.strengthText ?? "")
    }

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
                stockCard

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
        .navigationTitle(t("직접 입력", "Enter manually"))
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
                            .frame(width: 36, height: 36)
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
                Text(t("무슨 요일에", "On which days"))
                    .janjanBody(12, weight: .medium)
                    .foregroundStyle(Color.muted)

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

    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true

        let medication = Medication(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            strengthText: strength.trimmingCharacters(in: .whitespacesAndNewlines),
            form: form,
            kind: kind,
            purposeLine: purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let schedules: [Schedule] = (kind == .scheduled ? drafts.filter(\.isOn) : []).map { draft in
            Schedule(
                medicationID: medication.id,
                slot: draft.slot,
                timeOfDay: draft.timeOfDay,
                weekdays: weekdays,
                dosePerIntake: draft.dose
            )
        }

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
}

#Preview {
    NavigationStack {
        MedicationFormView {}
    }
    .modelContainer(for: JanjanSchema.allModels, inMemory: true)
}
