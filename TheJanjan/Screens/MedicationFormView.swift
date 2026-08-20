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

    @State private var name = ""
    @State private var strength = ""
    @State private var purpose = ""
    @State private var form: Medication.Form = .tablet
    @State private var kind: Medication.Kind = .scheduled
    @State private var weekdays: Set<Weekday> = Weekday.everyday
    @State private var stockText = ""
    @State private var drafts: [SlotDraft] = SlotDraft.presets()
    @State private var isSaving = false

    /// 시간대 한 줄의 초안. 켜진 것만 스케줄이 된다.
    private struct SlotDraft: Identifiable {
        let slot: DoseSlot
        var isOn: Bool
        /// DatePicker 가 Date 만 다뤄서 시·분을 Date 에 얹어 들고 있는다.
        var time: Date
        var dose: Decimal

        var id: String { slot.storageKey }

        var timeOfDay: TimeOfDay {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        }

        static func presets() -> [SlotDraft] {
            DoseSlot.presets.map { slot in
                SlotDraft(
                    slot: slot,
                    isOn: false,
                    time: slot.defaultTime.date(on: Date()),
                    dose: 1
                )
            }
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
        .navigationTitle("직접 입력")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 카드

    private var identityCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
                JanjanField(label: "이름", placeholder: "예: 에스시탈로프람", text: $name)
                JanjanField(label: "용량", placeholder: "예: 10mg", text: $strength)
                JanjanField(
                    label: "용도 한 줄 (선택)",
                    placeholder: "예: 잠들기 쉽게",
                    text: $purpose
                )
            }
        }
    }

    private var kindCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("어떻게 먹는 약인가요")
                    .font(JanjanFont.body(12, weight: .medium))
                    .foregroundStyle(Color.muted)

                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    ForEach(Medication.Kind.allCases, id: \.self) { option in
                        TogglePill(text: option.labelKo, isOn: kind == option) {
                            kind = option
                        }
                    }
                }

                Text("제형")
                    .font(JanjanFont.body(12, weight: .medium))
                    .foregroundStyle(Color.muted)
                    .padding(.top, CGFloat(JanjanSpacing.xs))

                Picker("제형", selection: $form) {
                    ForEach(Medication.Form.allCases, id: \.self) { option in
                        Text(option.labelKo).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.ink)

                if !form.isSplittable {
                    Text("이 제형은 쪼개 먹지 않는 것으로 보고 개수를 1정 단위로만 셉니다.")
                        .font(JanjanFont.body(12))
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var slotCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("언제 먹나요")
                    .font(JanjanFont.body(12, weight: .medium))
                    .foregroundStyle(Color.muted)

                ForEach(drafts.indices, id: \.self) { index in
                    slotRow(index)
                }
            }
        }
    }

    private func slotRow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
            HStack {
                TogglePill(text: drafts[index].slot.labelKo, isOn: drafts[index].isOn) {
                    drafts[index].isOn.toggle()
                }
                Spacer(minLength: CGFloat(JanjanSpacing.xs))
                if drafts[index].isOn {
                    DatePicker(
                        "",
                        selection: $drafts[index].time,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .accessibilityLabel(Text("\(drafts[index].slot.labelKo) 시각"))
                }
            }

            if drafts[index].isOn {
                doseStepper(index)
            }
        }
        .padding(.vertical, CGFloat(JanjanSpacing.xxs))
    }

    /// 1회 개수 조절. 시스템 Stepper 는 회색 시스템 컨트롤이라
    /// "칩과 버튼은 완전한 알약" 규칙(설계 02절)과 어긋나서 직접 짠다.
    private func doseStepper(_ index: Int) -> some View {
        HStack(spacing: CGFloat(JanjanSpacing.s)) {
            stepButton("minus", label: "개수 줄이기") { adjust(index, by: -doseStep) }

            Text("1회 \(DecimalQuantity.display(drafts[index].dose))정")
                .font(JanjanFont.body(14))
                .foregroundStyle(Color.ink2)
                .monospacedDigit()

            stepButton("plus", label: "개수 늘리기") { adjust(index, by: doseStep) }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }

    private func stepButton(
        _ systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            CircleGlyph(systemImage: systemImage, background: .surface2, diameter: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var weekdayCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("무슨 요일에")
                    .font(JanjanFont.body(12, weight: .medium))
                    .foregroundStyle(Color.muted)

                HStack(spacing: CGFloat(JanjanSpacing.xxs)) {
                    ForEach(Weekday.displayOrderKo, id: \.self) { day in
                        TogglePill(text: day.labelKo, isOn: weekdays.contains(day)) {
                            toggle(day)
                        }
                    }
                }

                if weekdays.isEmpty {
                    Text("하루도 고르지 않으면 알림이 가지 않아요.")
                        .font(JanjanFont.body(12))
                        .foregroundStyle(Color.muted)
                }
            }
        }
    }

    private var stockCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                JanjanField(
                    label: "지금 남은 개수 (선택)",
                    placeholder: "예: 28",
                    keyboard: .decimalPad,
                    text: $stockText
                )
                Text("세어 본 개수를 적으면 이 시점이 기준이 돼요. 비워 두면 재고를 세지 않아요.")
                    .font(JanjanFont.body(12))
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
        return drafts.contains { $0.isOn }
    }

    private func adjust(_ index: Int, by delta: Decimal) {
        let next = DecimalQuantity.snapToQuarter(drafts[index].dose + delta)
        drafts[index].dose = max(next, doseStep)
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
