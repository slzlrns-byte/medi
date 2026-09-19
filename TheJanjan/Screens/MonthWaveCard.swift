import SwiftUI
import SwiftData
import UIKit
import JanjanCore

/// 리포트 · "이번 달의 물결".
///
/// 한 달의 기분 색이 한 장의 그림이 된다. 숫자·추세·해석은 붙이지 않는다 —
/// 색만 보여 주면 해석은 본인이 한다. "좋아져야 한다" 는 압박이 생기는 순간
/// 이 카드는 기록을 막는 카드가 된다.
///
/// **내보내는 그림에 약 이름은 없다.** 기분 색과 날짜뿐이라, 올린 사람이 무엇을
/// 먹는지는 그림이 말하지 않는다. 그래서 이 그림만은 바깥에 올려도 안전하다.
struct MonthWaveCard: View {

    let checkIns: [CheckIn]

    /// 보고 있는 달. 지난달로 넘겨 볼 수 있다.
    @State private var shownMonth = Date()
    @State private var exportImage: ExportImage?
    /// 누른 날. 그날의 기록을 시트로 보여 준다(사용자 요청 2026-09-19).
    @State private var selectedDay: SelectedDay?

    private struct ExportImage: Identifiable {
        let image: UIImage
        let id = UUID()
    }

    private struct SelectedDay: Identifiable {
        let date: Date
        var id: Date { date }
    }

    private var calendar: Calendar { .current }

    private var wave: MonthWave {
        MonthWave.make(containing: shownMonth, checkIns: checkIns, calendar: calendar)
    }

    private var isShowingCurrentMonth: Bool {
        calendar.isDate(shownMonth, equalTo: Date(), toGranularity: .month)
    }

    var body: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                header
                MonthWaveGrid(wave: wave, today: Date(), calendar: calendar) { day in
                    var components = DateComponents()
                    components.year = wave.year
                    components.month = wave.month
                    components.day = day
                    if let date = calendar.date(from: components) {
                        selectedDay = SelectedDay(date: date)
                    }
                }
                footer
            }
        }
        .sheet(item: $exportImage) { file in
            ShareSheet(items: [file.image])
        }
        .sheet(item: $selectedDay) { selected in
            DayRecordSheet(date: selected.date)
        }
    }

    private var header: some View {
        HStack(spacing: CGFloat(JanjanSpacing.xs)) {
            Text(t("이번 달의 흐름", "This month's flow"))
                .janjanDisplay(20)
                .foregroundStyle(Color.ink)
            Spacer(minLength: 0)
            monthButton("chevron.left", labelKo: t("지난달", "Previous month")) {
                move(by: -1)
            }
            Text(monthYearText)
                .janjanBody(14)
                .foregroundStyle(Color.muted)
                .fixedSize()
            monthButton("chevron.right", labelKo: t("다음 달", "Next month")) {
                move(by: 1)
            }
            .disabled(isShowingCurrentMonth)
            .opacity(isShowingCurrentMonth ? 0.3 : 1)
        }
    }

    private var monthYearText: String { monthWaveYearMonthText(wave) }

    private func monthButton(_ systemImage: String, labelKo: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink2)
                // 아이콘은 작아도 누르는 자리는 44pt 를 지킨다.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(labelKo))
    }

    private var footer: some View {
        // 설명 문장은 사용자 결정(2026-09-16)으로 뺐다 - 그림만 있으면 된다.
        HStack(alignment: .bottom) {
            Spacer(minLength: CGFloat(JanjanSpacing.s))
            WhitePillButton(title: t("그림으로 저장", "Save as image"), systemImage: "square.and.arrow.down") {
                export()
            }
        }
    }

    private func move(by value: Int) {
        if let moved = calendar.date(byAdding: .month, value: value, to: shownMonth) {
            shownMonth = moved
        }
    }

    /// 지금 보고 있는 그대로를 한 장으로 만든다.
    @MainActor
    private func export() {
        let renderer = ImageRenderer(
            content: MonthWaveShareView(wave: wave, today: Date(), calendar: calendar)
                .frame(width: 420)
        )
        renderer.scale = 3
        if let image = renderer.uiImage {
            exportImage = ExportImage(image: image)
        }
    }
}

/// 달력 본체. 화면과 내보내는 그림이 같은 것을 그린다.
///
/// LazyVGrid 를 쓰지 않는다 — ImageRenderer 는 화면 밖에서 그리는데, 게으른
/// 컨테이너는 화면 밖에서 셀을 만들지 않을 수 있다. 줄을 손으로 잘라 그린다.
private struct MonthWaveGrid: View {

    let wave: MonthWave
    let today: Date
    let calendar: Calendar
    /// 지나간(또는 오늘) 날짜를 누르면 불린다. 내보내는 그림에서는 nil 이다.
    var onSelectDay: ((Int) -> Void)? = nil

    private let spacing: CGFloat = 6

    private var weekdaySymbols: [String] {
        JanjanLanguage.current == .english
            ? ["S", "M", "T", "W", "T", "F", "S"]
            : ["일", "월", "화", "수", "목", "금", "토"]
    }

    /// 앞뒤 빈 칸을 채워 7칸씩 자른 줄들.
    private var rows: [[MonthWave.DayCell?]] {
        var cells: [MonthWave.DayCell?] = Array(repeating: nil, count: wave.leadingBlanks)
        cells += wave.days.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
    }

    var body: some View {
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .janjanBody(11)
                        .foregroundStyle(Color.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        dayCell(cell)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ cell: MonthWave.DayCell?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if let cell {
                let body = ZStack(alignment: .topTrailing) {
                    if let score = cell.moodScore {
                        shape.fill(Color.mood(score))
                    } else if isFuture(cell.day) {
                        // 아직 오지 않은 날. 아무 말도 하지 않는 옅은 칸.
                        shape.fill(Color.janjan(.surface2).opacity(0.45))
                    } else {
                        // 지나갔는데 기록이 없는 날. 점선일 뿐, 채우라는 재촉이 아니다.
                        shape.strokeBorder(
                            Color.janjan(.line2),
                            style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                        )
                    }
                    Text("\(cell.day)")
                        .janjanBody(10, weight: .medium)
                        .foregroundStyle(numberColor(cell))
                        .padding(5)
                }
                .accessibilityLabel(Text(accessibilityText(cell)))

                // 지나간 날은 눌러서 그날 기록을 본다. 미래 칸은 볼 것이 없다.
                if let onSelectDay, !isFuture(cell.day) {
                    Button {
                        onSelectDay(cell.day)
                    } label: {
                        body.contentShape(shape)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text(t("이날의 기록을 봐요.", "See this day's records.")))
                } else {
                    body
                }
            } else {
                Color.clear
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private func isFuture(_ day: Int) -> Bool {
        var components = DateComponents()
        components.year = wave.year
        components.month = wave.month
        components.day = day
        guard let date = calendar.date(from: components) else { return false }
        return date > calendar.startOfDay(for: today)
    }

    private func numberColor(_ cell: MonthWave.DayCell) -> Color {
        guard let score = cell.moodScore else { return Color.muted.opacity(0.7) }
        // 짙은 색 위에서는 흰 글자, 옅은 색 위에서는 먹색.
        return abs(score) >= 2 ? Color.janjan(.surface) : Color.ink.opacity(0.55)
    }

    private func accessibilityText(_ cell: MonthWave.DayCell) -> String {
        guard let score = cell.moodScore else {
            return t("\(cell.day)일, 기록 없음", "Day \(cell.day), no record")
        }
        let label = CheckIn.Mood(score).label(JanjanLanguage.current)
        return t("\(cell.day)일, \(label)", "Day \(cell.day), \(label)")
    }
}

/// 달과 해를 한 줄로. 화면 헤더와 내보내는 그림이 같은 것을 쓴다.
private func monthWaveYearMonthText(_ wave: MonthWave) -> String {
    guard JanjanLanguage.current == .english else {
        return "\(String(wave.year))년 \(wave.month)월"
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: JanjanLanguage.current.localeIdentifier)
    let name = formatter.monthSymbols[min(max(wave.month - 1, 0), 11)]
    return "\(name) \(String(wave.year))"
}

/// 내보내는 한 장. 종이색 바탕에 달력과 달 이름, 작은 앱 이름뿐이다.
private struct MonthWaveShareView: View {

    let wave: MonthWave
    let today: Date
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
            HStack(alignment: .lastTextBaseline) {
                Text(t("이번 달의 흐름", "This month's flow"))
                    .janjanDisplay(24)
                    .foregroundStyle(Color.ink)
                Spacer()
                Text(monthWaveYearMonthText(wave))
                    .janjanBody(15)
                    .foregroundStyle(Color.muted)
            }
            MonthWaveGrid(wave: wave, today: today, calendar: calendar)
            HStack {
                Spacer()
                Text(Janjan.appName(JanjanLanguage.current))
                    .janjanBody(12, weight: .medium)
                    .foregroundStyle(Color.muted)
            }
        }
        .padding(CGFloat(JanjanSpacing.xl))
        .background(Color.janjan(.fog))
    }
}

/// 달력에서 누른 하루의 기록을 모아 보여 주는 시트 (사용자 요청 2026-09-19).
///
/// 보여 주는 것이 먼저이고, 고치는 것은 한 겹 안에 있다 - "이날 기록 고치기"
/// 가 기록 화면을 그 날짜로 연다(QA 2026-09-19. 그 전에는 보기 전용이라
/// 어제 기분을 잘못 눌러도 손댈 방법이 없었다).
/// 목록을 통째로 읽고 날짜로 거르는 것은 이 앱의 다른 화면과 같은 규칙이다.
private struct DayRecordSheet: View {

    let date: Date

    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var isEditingDoses = false
    /// 이미 남아 있는 기록을 고치러 들어가기 전에 한 번 묻는다. 비어 있던
    /// 날을 뒤늦게 채우는 것은 묻지 않는다 - 없던 것이 생기는 일에는
    /// 되돌릴 것이 없다(사용자 요청 2026-09-19).
    @State private var isConfirmingEdit = false

    @Query private var checkInRecords: [CheckInRecord]
    @Query private var symptomRecords: [SymptomEntryRecord]
    @Query private var doseRecords: [DoseEventRecord]

    private var calendar: Calendar { .current }
    private var lang: JanjanLanguage { .current }

    private var checkIn: CheckInRecord? {
        checkInRecords
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private var symptoms: [SymptomEntryRecord] {
        symptomRecords
            .filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private var doses: [DoseEventRecord] {
        doseRecords.filter { calendar.isDate($0.scheduledAt, inSameDayAs: date) }
    }

    private var hasAnything: Bool {
        checkIn != nil || !symptoms.isEmpty || !doses.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                    if let checkIn {
                        moodCard(checkIn)
                    }
                    if !doses.isEmpty {
                        doseCard
                    }
                    if !symptoms.isEmpty {
                        symptomsCard
                    }
                    if !hasAnything {
                        JanjanCard {
                            Text(t("이날은 남긴 기록이 없어요.", "Nothing was logged on this day."))
                                .janjanBody(14)
                                .foregroundStyle(Color.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // **버튼 이름이 범위를 말해야 한다.** "이날 기록 고치기" 는
                    // 복약 표시까지 고쳐 줄 것처럼 보이는데 그쪽은 다른 문이다
                    // (QA 2026-09-19).
                    WhitePillButton(
                        title: hasAnything
                            ? t("기분·증상 고치기", "Edit mood and symptoms")
                            : t("이날 기록 남기기", "Log this day"),
                        systemImage: "pencil"
                    ) {
                        if hasAnything {
                            isConfirmingEdit = true
                        } else {
                            isEditing = true
                        }
                    }
                    .padding(.top, CGFloat(JanjanSpacing.xs))

                    // 잘못 눌린 "건너뜀" 을 고칠 자리가 앱 어디에도 없었다.
                    // 진료실에 나가는 숫자라 고칠 길이 있어야 한다.
                    WhitePillButton(
                        title: t("복약 기록 고치기", "Edit doses"),
                        systemImage: "pills"
                    ) {
                        isEditingDoses = true
                    }
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.top, CGFloat(JanjanSpacing.s))
                .padding(.bottom, CGFloat(JanjanSpacing.xxl))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $isEditing) {
            DiaryView(day: date)
        }
        .sheet(isPresented: $isEditingDoses) {
            DayDoseEditSheet(date: date)
        }
        .confirmationDialog(
            t("정말 고치시겠습니까?", "Edit this past entry?"),
            isPresented: $isConfirmingEdit,
            titleVisibility: .visible
        ) {
            Button(t("고치기", "Edit")) { isEditing = true }
            Button(t("취소", "Cancel"), role: .cancel) { isConfirmingEdit = false }
        } message: {
            Text(t(
                "지난 기록을 고치면 리포트와 한 달의 흐름에도 새 값으로 나와요.",
                "Editing a past entry changes what your report and monthly flow show."
            ))
        }
    }

    private var titleText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: lang.localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("MMMMdEEE")
        return formatter.string(from: date)
    }

    private func moodCard(_ record: CheckInRecord) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    Circle()
                        .fill(Color.mood(record.moodScore))
                        .frame(width: 18, height: 18)
                    Text(CheckIn.Mood(record.moodScore).label(lang))
                        .janjanBody(15, weight: .medium)
                        .foregroundStyle(Color.ink)
                    Spacer(minLength: 0)
                    if let minutes = record.sleepMinutes {
                        PillChip(text: sleepText(minutes))
                    }
                }

                if let note = record.note, !note.isEmpty {
                    Text(note)
                        .janjanBody(14)
                        .foregroundStyle(Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !record.emotionWords.isEmpty {
                    Text(record.emotionWords
                        .map { Catalogs.emotions.word(id: $0)?.name(lang) ?? $0 }
                        .joined(separator: " · "))
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !record.activities.isEmpty {
                    Text(record.activities
                        .map { ActivityTag.name(forID: $0, language: lang) }
                        .joined(separator: " · "))
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let dream = record.dreamNote, !dream.isEmpty {
                    Text(t("꿈 - \(dream)", "Dream - \(dream)"))
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 복약은 개수로만 말한다 - 이름 가리기와 무관하게 안전한 요약이다.
    private var doseCard: some View {
        let taken = doses.filter { $0.statusRaw == DoseEvent.Status.taken.rawValue }
        let skipped = doses.filter { $0.statusRaw == DoseEvent.Status.skipped.rawValue }
        let rescue = taken.filter { $0.kindRaw == DoseEvent.Kind.asNeeded.rawValue }

        return JanjanCard {
            HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                PillChip(text: t("복용 \(taken.count - rescue.count)", "Taken \(taken.count - rescue.count)"))
                if !skipped.isEmpty {
                    PillChip(text: t("건너뜀 \(skipped.count)", "Skipped \(skipped.count)"))
                }
                if !rescue.isEmpty {
                    PillChip(text: t("비상약 \(rescue.count)", "Rescue \(rescue.count)"))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var symptomsCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text(t("증상", "Symptoms"))
                    .janjanBody(13, weight: .medium)
                    .foregroundStyle(Color.muted)
                ForEach(symptoms) { entry in
                    HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                        Text(Catalogs.symptoms.symptom(id: entry.symptomID)?.name(lang) ?? entry.symptomID)
                            .janjanBody(14)
                            .foregroundStyle(Color.ink2)
                        PillChip(text: t("세기 \(entry.severity)", "Severity \(entry.severity)"))
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func sleepText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if lang == .english {
            return rest == 0 ? "\(hours)h sleep" : "\(hours)h \(rest)m sleep"
        }
        return rest == 0 ? "수면 \(hours)시간" : "수면 \(hours)시간 \(rest)분"
    }
}

/// 지난 날의 복약 표시를 고치는 시트 (QA 2026-09-19).
///
/// **왜 필요한가.** 잘못 눌린 "건너뜀" 을 고칠 자리가 앱 어디에도 없었다.
/// 답이 없는 시간대는 "기록 없이 지나간 시간대" 가 물어보지만, 한 번 답한
/// 것은 그것으로 굳었다. 그 표시는 복약률이 되어 진료실로 나간다.
///
/// 계획은 저장돼 있지 않고 매번 다시 만들어지므로(DayPlan), 여기서도 그
/// 날의 계획을 다시 세워 놓고 그 위에 답을 얹는다. 약이 없던 날에는
/// 계획도 없다 - 등록 전 날짜가 여기 올라오지 않는 이유다.
private struct DayDoseEditSheet: View {

    let date: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query private var medicationRecords: [MedicationRecord]
    @Query private var scheduleRecords: [ScheduleRecord]
    @Query private var doseRecords: [DoseEventRecord]

    private var calendar: Calendar { .current }
    private var lang: JanjanLanguage { .current }
    private var masksNames: Bool { JanjanPrivacy.hidesNames }

    private var lines: [DayPlan.SlotLine] {
        DayPlan.slots(
            on: date,
            schedules: scheduleRecords.map(\.core),
            medications: medicationRecords.map { $0.core.displayReady },
            doseEvents: doseRecords.map(\.core),
            calendar: calendar
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                    Text(t(
                        "이날의 복약 표시를 고쳐요. 고치면 복약률과 리포트에도 새 값으로 나와요.",
                        "Fix this day's dose marks. Your adherence and report update with them."
                    ))
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if lines.isEmpty {
                        JanjanCard {
                            Text(t(
                                "이날은 예정된 약이 없었어요.",
                                "Nothing was scheduled on this day."
                            ))
                                .janjanBody(14)
                                .foregroundStyle(Color.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    ForEach(lines) { line in
                        slotCard(line)
                    }
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.top, CGFloat(JanjanSpacing.s))
                .padding(.bottom, CGFloat(JanjanSpacing.xxl))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle(t("복약 기록 고치기", "Edit doses"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func slotCard(_ line: DayPlan.SlotLine) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(line.slot.isCustom
                     ? line.time.description
                     : "\(line.slot.label(lang)) \(line.time.description)")
                    .janjanBody(16, weight: .medium)
                    .foregroundStyle(Color.ink)

                ForEach(line.entries) { entry in
                    VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                        HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                            MaskedNameText(name: entry.medicationName, isMasked: masksNames)
                                .janjanBody(14, weight: .medium)
                                .foregroundStyle(Color.ink)
                                .lineLimit(1)
                            PillChip(text: t(
                                "\(DecimalQuantity.display(entry.dose))정",
                                pillsEn(entry.dose)
                            ))
                            Spacer(minLength: 0)
                            // 지금 무엇으로 적혀 있는지를 먼저 말한다. 색이
                            // 아니라 글자로 - 상태를 색으로만 말하지 않는다.
                            PillChip(
                                text: statusText(entry),
                                tint: entry.status == .taken ? .sage : .surface2,
                                textTint: entry.status == .taken ? .sageInk : .ink2
                            )
                        }
                        AnswerPillRow(answers: [
                            .init(t("먹었어요", "Took it")) { record(entry, in: line, as: .taken) },
                            .init(t("건너뛰었어요", "Skipped it")) { record(entry, in: line, as: .skipped) },
                            .init(t("기억나지 않아요", "I don't remember")) {
                                record(entry, in: line, as: .unrecorded)
                            }
                        ])
                    }
                    .padding(.vertical, CGFloat(JanjanSpacing.xxs))
                }
            }
        }
    }

    /// 앱이 채워 둔 미기록과 사용자가 고른 미기록을 화면에서도 가른다.
    private func statusText(_ entry: DayPlan.Entry) -> String {
        guard let status = entry.status else { return t("답 없음", "No answer") }
        if status == .unrecorded, entry.source == .automatic {
            return t("답 없음", "No answer")
        }
        return status.label(lang)
    }

    private func record(
        _ entry: DayPlan.Entry,
        in line: DayPlan.SlotLine,
        as status: DoseEvent.Status
    ) {
        DoseRecorder.record(
            medicationID: entry.medicationID,
            slotKey: line.slot.storageKey,
            status: status,
            source: .phone,
            on: date,
            at: line.time.date(on: date, calendar: calendar),
            quantity: entry.dose,
            in: context,
            calendar: calendar
        )
        try? context.save()
        AppServices.shared.pushWatchSnapshot()
    }
}
