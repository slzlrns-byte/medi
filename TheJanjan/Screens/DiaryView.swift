import SwiftUI
import SwiftData
import JanjanCore

/// 기록 — 감정·증상 일기 (설계 03절 · 09절).
///
/// **2층 구조.** 1층은 기분 원 하나다. 그것만 고르고 나가도 완전한 기록이고,
/// 앱은 빈 칸을 재촉하지 않는다. 2층(감정 단어·에너지·불안·수면·활동·긴 글)은
/// 접혀 있다가 사용자가 열 때만 펼쳐진다.
///
/// 저장은 곧바로 일어난다. "저장" 버튼이 없다 — 누르지 않아 기록이 사라지는 일을
/// 만들지 않기 위해서다. SwiftData 가 바뀐 값을 그대로 써 준다.
struct DiaryView: View {

    /// 들여다보는 날. nil 이면 오늘이고, 그때만 탭 화면으로 동작한다.
    ///
    /// 지난 날의 기분과 메모를 고칠 길이 없었다(QA 2026-09-19). 어제 기분을
    /// 잘못 눌렀거나 오타가 있어도 손댈 방법이 없었는데, 이것은 리포트에
    /// 실려 진료실까지 나가는 값이다. 고치는 화면을 따로 만들지 않고 같은
    /// 화면을 날짜만 바꿔 연다 - 두 벌로 나누면 한쪽만 고쳐지는 날이 온다.
    private let day: Date?

    init(day: Date? = nil) { self.day = day }

    /// 지난 날을 고치러 열린 상태인가. 그날 것이 아닌 카드(오늘의 질문·
    /// 이번 달의 흐름·지난 기록)는 이때 감춘다.
    private var isDayEditor: Bool { day != nil }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CheckInRecord.date, order: .reverse) private var checkInRecords: [CheckInRecord]
    @Query(sort: \SymptomEntryRecord.startedAt, order: .reverse)
    private var symptomRecords: [SymptomEntryRecord]

    @State private var isExpanded = false
    @State private var isShowingSymptomSheet = false
    @State private var pendingSymptomDeletion: SymptomEntryRecord?
    @State private var safetyReason: SafetyReason?
    /// 고치러 여는 지난 날.
    @State private var editingDay: EditingDay?
    /// 고치기 전에 한 번 묻는 자리. 지난 기록은 이미 리포트에 실린 값이라
    /// 무심코 눌러서 바뀌면 안 된다(사용자 요청 2026-09-19).
    @State private var pendingEditDay: EditingDay?

    /// 시트에 넘길 때 Identifiable 이 필요해 감싼다.
    private struct EditingDay: Identifiable {
        let id = UUID()
        let date: Date
    }
    /// 글 칸 어디에든 커서가 있으면 참. 키보드 위 "완료" 가 이걸 꺼서
    /// 키보드를 내린다(사용자 요청 2026-09-19) - 여러 줄 칸은 리턴이
    /// 줄바꿈이라 달리 내릴 길이 없다.
    @FocusState private var isEditingText: Bool

    /// 시트에 넘길 때 Identifiable 이 필요해 감싼다.
    private struct SafetyReason: Identifiable {
        let id = UUID()
        let reason: SafetyTrigger.Reason
    }

    @ObservedObject private var clock = JanjanClock.shared
    private var viewedDay: Date { day ?? clock.today }
    private var calendar: Calendar { .current }

    private var dayRecord: CheckInRecord? {
        // 동기화 충돌로 같은 날 두 줄이 생겼어도 가장 나중에 손댄 줄을 편집한다.
        // first 로 고르면 어느 줄이 걸릴지 기기마다 달라진다.
        checkInRecords
            .filter { calendar.isDate($0.date, inSameDayAs: viewedDay) }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private var daySymptoms: [SymptomEntryRecord] {
        symptomRecords.filter { calendar.isDate($0.startedAt, inSameDayAs: viewedDay) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
                    moodCard

                    if let record = dayRecord {
                        noteCard(record)
                        lifestyleCard(record)
                        expandButton
                        if isExpanded {
                            emotionWordCard(record)
                            scaleCard(record)
                            sleepCard(record)
                            activityCard(record)
                            longTextCard(record)
                        }
                    }

                    symptomCard
                    // 오늘의 질문·한 달의 흐름·지난 기록은 그날 하나의 것이
                    // 아니다. 지난 날을 고치러 들어온 화면에는 두지 않는다.
                    if !isDayEditor {
                        questionCard
                        // 리포트에도 같은 카드가 있지만, 기분을 적는 자리에서 바로
                        // 한 달을 돌아볼 수 있어야 한다. 계산은 MonthWave 한 곳이 한다.
                        MonthWaveCard(checkIns: checkInRecords.map(\.core))
                        historyCard
                    }
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.bottom, CGFloat(JanjanSpacing.xxl))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            // 다른 곳을 누르거나 스크롤하면 키보드가 내려간다(사용자 요청 2026-09-19).
            // simultaneousGesture 라 버튼·칩 탭은 그대로 동작한다.
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(TapGesture().onEnded { isEditingText = false })
            .navigationTitle(isDayEditor ? dayTitleText : t("기록", "Journal"))
            .navigationBarTitleDisplayMode(isDayEditor ? .inline : .large)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(t("완료", "Done")) { isEditingText = false }
                        .foregroundStyle(Color.ink)
                }
                if isDayEditor {
                    // 저장 버튼은 없다 - 고친 것은 그때그때 저장된다.
                    // 닫기만 있으면 된다(기록 화면과 같은 규칙).
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(t("닫기", "Close")) { dismiss() }
                            .foregroundStyle(Color.ink)
                    }
                }
            }
            .sheet(isPresented: $isShowingSymptomSheet) {
                SymptomEntrySheet { symptomID, severity, note in
                    saveSymptom(symptomID: symptomID, severity: severity, note: note)
                }
            }
            .sheet(item: $safetyReason) { _ in
                SafetyCardView()
            }
            .sheet(item: $editingDay) { target in
                DiaryView(day: target.date)
            }
            // 지난 기록은 이미 지나간 날의 사실이고 리포트에도 실린다.
            // 고치는 일 자체를 막지는 않되, 한 번은 묻고 들어간다.
            .confirmationDialog(
                t("정말 고치시겠습니까?", "Edit this past entry?"),
                isPresented: Binding(
                    get: { pendingEditDay != nil },
                    set: { if !$0 { pendingEditDay = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingEditDay
            ) { target in
                Button(t("고치기", "Edit")) {
                    pendingEditDay = nil
                    editingDay = target
                }
                Button(t("취소", "Cancel"), role: .cancel) { pendingEditDay = nil }
            } message: { _ in
                Text(t(
                    "지난 기록을 고치면 리포트와 한 달의 흐름에도 새 값으로 나와요.",
                    "Editing a past entry changes what your report and monthly flow show."
                ))
            }
            .confirmationDialog(
                t("이 증상 기록을 지울까요?", "Delete this symptom entry?"),
                isPresented: Binding(
                    get: { pendingSymptomDeletion != nil },
                    set: { if !$0 { pendingSymptomDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingSymptomDeletion
            ) { entry in
                Button(t("지우기", "Delete"), role: .destructive) { delete(entry) }
                Button(t("취소", "Cancel"), role: .cancel) { pendingSymptomDeletion = nil }
            }
        }
    }

    // MARK: - 1층

    private var moodCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(isDayEditor
                     ? t("이날 기분은 어떠셨어요?", "How did this day feel?")
                     : t("지금 기분은 어떠세요?", "How are you feeling right now?"))
                    .janjanDisplay(22)
                    .foregroundStyle(Color.ink)

                MoodPickerRow(chosenScore: dayRecord?.moodScore) { saveMood($0) }

                if let record = dayRecord {
                    Text(CheckIn.Mood(record.moodScore).label(JanjanLanguage.current))
                        .janjanBody(14, weight: .medium)
                        .foregroundStyle(Color.ink2)
                } else {
                    Text(t("하나만 골라도 완전한 기록이에요.", "Choosing just one is still a complete entry."))
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)
                }
            }
        }
    }

    private func noteCard(_ record: CheckInRecord) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text(t("한 줄 남길까요?", "Want to leave a note?"))
                    .janjanBody(15, weight: .medium)
                    .foregroundStyle(Color.ink)
                TextField("", text: text(record, \.note), axis: .vertical)
                    .focused($isEditingText)
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

    /// 술·담배 원탭 (사용자 결정 2026-09-10). 2층의 활동 칩과 같은 저장소를 쓴다 —
    /// 어느 쪽에서 누르든 한 곳(activities)에 적힌다. 여기 따로 둔 이유는
    /// 약과 영향을 주고받아 진료 때 자주 묻는 항목이라, 2층을 펼치지 않은
    /// 날에도 손이 닿아야 해서다.
    private func lifestyleCard(_ record: CheckInRecord) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    TogglePill(
                        text: t("술 마셨어요", "Had alcohol"),
                        isOn: record.activities.contains(ActivityTag.alcoholID)
                    ) {
                        toggleActivity(ActivityTag.alcoholID, in: record)
                    }
                    TogglePill(
                        text: t("담배 피웠어요", "Smoked"),
                        isOn: record.activities.contains(ActivityTag.smokingID)
                    ) {
                        toggleActivity(ActivityTag.smokingID, in: record)
                    }
                }
                Text(t("진료 때 자주 묻는 항목이라 리포트에 함께 실려요.", "This is often asked at visits, so it's included in the report."))
                    .janjanBody(12)
                    .foregroundStyle(Color.muted)
            }
        }
    }

    private var expandButton: some View {
        WhitePillButton(
            title: isExpanded ? t("접기", "Show less") : t("더 남기기", "Add more"),
            systemImage: isExpanded ? "chevron.up" : "chevron.down"
        ) {
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
        }
    }

    // MARK: - 2층

    private func emotionWordCard(_ record: CheckInRecord) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(t("어떤 마음이었어요?", "What did it feel like?"))
                    .janjanBody(15, weight: .medium)
                    .foregroundStyle(Color.ink)

                // 좋은/나쁜을 색으로 편 가르지 않는다. 전부 같은 회색 칩.
                FlowRow(spacing: CGFloat(JanjanSpacing.xs)) {
                    ForEach(Catalogs.emotions.words) { word in
                        let isOn = record.emotionWords.contains(word.id)
                        Button {
                            toggle(word.id, in: record)
                        } label: {
                            PillChip(
                                text: word.name(JanjanLanguage.current),
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

    private func scaleCard(_ record: CheckInRecord) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
                scaleRow(t("기운", "Energy"), value: optionalInt(record, \.energy))
                scaleRow(t("불안", "Anxiety"), value: optionalInt(record, \.anxiety))
            }
        }
    }

    /// 1~5 다섯 칸. 고르지 않은 상태로 되돌릴 수 있게 고른 칸을 다시 누르면 지워진다.
    private func scaleRow(_ title: String, value: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
            HStack {
                Text(title)
                    .janjanBody(15, weight: .medium)
                    .foregroundStyle(Color.ink)
                Spacer()
                if value.wrappedValue == nil {
                    Text(t("안 적음", "Not set"))
                        .janjanBody(12)
                        .foregroundStyle(Color.muted)
                }
            }
            HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                ForEach(1...5, id: \.self) { step in
                    TogglePill(text: "\(step)", isOn: value.wrappedValue == step) {
                        value.wrappedValue = (value.wrappedValue == step) ? nil : step
                    }
                }
            }
        }
    }

    private func sleepCard(_ record: CheckInRecord) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(t("잠은 어땠어요?", "How did you sleep?"))
                    .janjanBody(15, weight: .medium)
                    .foregroundStyle(Color.ink)

                CountStepper(
                    text: sleepText(record),
                    decreaseLabelKo: t("잔 시간 줄이기", "Decrease sleep time"),
                    increaseLabelKo: t("잔 시간 늘리기", "Increase sleep time"),
                    onDecrease: { adjustSleep(record, by: -30) },
                    onIncrease: { adjustSleep(record, by: 30) }
                )

                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    ForEach(CheckIn.SleepQuality.allCases, id: \.self) { quality in
                        TogglePill(
                            text: quality.label(JanjanLanguage.current),
                            isOn: record.sleepQualityRaw == quality.rawValue
                        ) {
                            record.sleepQualityRaw =
                                (record.sleepQualityRaw == quality.rawValue) ? nil : quality.rawValue
                            touch(record)
                        }
                    }
                }

                TogglePill(text: t("꿈을 꿨어요", "Had a dream"), isOn: record.dreamed == true) {
                    record.dreamed = (record.dreamed == true) ? nil : true
                    touch(record)
                }

                // 토글이 꺼져 있으면 아래 3척도는 접어 둘 뿐 지우지 않는다.
                // 실수로 "꿈을 꿨어요" 를 껐다가 다시 켠 사람이 이미 적어 둔
                // 생생함·악몽·기억·한 줄을 그대로 다시 볼 수 있어야 한다.
                if record.dreamed == true {
                    dreamScaleRow(t("생생함", "Vividness"), value: optionalInt(record, \.dreamVividness))

                    TogglePill(text: t("악몽이었어요", "It was a nightmare"), isOn: record.nightmare == true) {
                        record.nightmare = (record.nightmare == true) ? nil : true
                        touch(record)
                    }

                    dreamScaleRow(t("기억", "Recall"), value: optionalInt(record, \.dreamRecall))

                    TextField(t("꿈 한 줄 (선택)", "A line about the dream (optional)"), text: text(record, \.dreamNote), axis: .vertical)
                        .focused($isEditingText)
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
    }

    /// 꿈 3척도 전용 1~3 세 칸. scaleRow 의 1~5 패턴과 같되 칸 수만 다르다.
    /// 고른 칸을 다시 누르면 nil 로 되돌린다.
    private func dreamScaleRow(_ title: String, value: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
            HStack {
                Text(title)
                    .janjanBody(15, weight: .medium)
                    .foregroundStyle(Color.ink)
                Spacer()
                if value.wrappedValue == nil {
                    Text(t("안 적음", "Not set"))
                        .janjanBody(12)
                        .foregroundStyle(Color.muted)
                }
            }
            HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                ForEach(1...3, id: \.self) { step in
                    TogglePill(text: "\(step)", isOn: value.wrappedValue == step) {
                        value.wrappedValue = (value.wrappedValue == step) ? nil : step
                    }
                }
            }
        }
    }

    private func activityCard(_ record: CheckInRecord) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(t("무엇을 했어요?", "What did you do?"))
                    .janjanBody(15, weight: .medium)
                    .foregroundStyle(Color.ink)

                FlowRow(spacing: CGFloat(JanjanSpacing.xs)) {
                    ForEach(ActivityTag.presets) { tag in
                        let isOn = record.activities.contains(tag.id)
                        Button {
                            toggleActivity(tag.id, in: record)
                        } label: {
                            PillChip(
                                text: tag.name(JanjanLanguage.current),
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

    private func longTextCard(_ record: CheckInRecord) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text(t("더 쓰고 싶으면", "If you want to write more"))
                    .janjanBody(15, weight: .medium)
                    .foregroundStyle(Color.ink)

                TextEditor(text: text(record, \.longText))
                    .focused($isEditingText)
                    .janjanBody(15)
                    .foregroundStyle(Color.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(CGFloat(JanjanSpacing.xs))
                    .background(
                        RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.row), style: .continuous)
                            .fill(Color.janjan(.surface2))
                    )

                Text(t("길이 제한은 없어요.", "There's no length limit."))
                    .janjanBody(12)
                    .foregroundStyle(Color.muted)
            }
        }
    }

    // MARK: - 증상

    private var symptomCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(t("증상", "Symptoms"))
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)

                if daySymptoms.isEmpty {
                    Text(isDayEditor
                         ? t("이날 남긴 증상이 없어요.", "No symptoms logged on this day.")
                         : t("오늘 남긴 증상이 없어요.", "No symptoms logged today."))
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)
                } else {
                    ForEach(daySymptoms) { entry in
                        symptomRow(entry)
                    }
                }

                WhitePillButton(title: t("증상 남기기", "Log a symptom"), systemImage: "plus") {
                    isShowingSymptomSheet = true
                }
                .padding(.top, CGFloat(JanjanSpacing.xxs))
            }
        }
    }

    private func symptomRow(_ entry: SymptomEntryRecord) -> some View {
        HStack(spacing: CGFloat(JanjanSpacing.xs)) {
            Text(Catalogs.symptoms.symptom(id: entry.symptomID)?.name(JanjanLanguage.current) ?? entry.symptomID)
                .janjanBody(15)
                .foregroundStyle(Color.ink2)
            PillChip(text: t("세기 \(entry.severity)", "Severity \(entry.severity)"))
            Spacer(minLength: 0)
            Button {
                // 바로 지우지 않는다. 12pt 글리프를 잘못 스치면 기록이 사라지고,
                // 약 삭제에는 확인을 붙여 두고 여기만 안 붙이는 것도 앞뒤가 안 맞는다.
                pendingSymptomDeletion = entry
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(t("이 증상 기록 지우기", "Delete this symptom entry")))
        }
    }

    // MARK: - 질문과 지난 기록

    private var questionCard: some View {
        let card = Catalogs.questions.card(for: viewedDay)
        return JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text(t("오늘의 질문", "Today's question"))
                    .janjanBody(12, weight: .medium)
                    .foregroundStyle(Color.muted)
                // 질문은 한 문장이 카드를 통째로 채운다. 줄바꿈이 어절
                // 한가운데서 일어나지 않게 어절 우선 규칙을 걸어 둔다.
                Text(JanjanText.wordWrapped(
                    card?.text(JanjanLanguage.current)
                        ?? t("오늘은 그냥 여기까지여도 괜찮아요.", "It's okay to stop here for today.")
                ))
                    .janjanDisplay(19)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 지난 2주. 숫자도 그래프도 없이 점과 글자만 — 되돌아보기지 평가가 아니다.
    private var historyCard: some View {
        let past = checkInRecords
            .filter { !calendar.isDate($0.date, inSameDayAs: viewedDay) }
            .prefix(14)

        return JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(t("지난 기록", "Past entries"))
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)

                if past.isEmpty {
                    Text(t("아직 지난 기록이 없어요.", "No past entries yet."))
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)
                }

                if !past.isEmpty {
                    Text(t("한 줄을 누르면 그날 기록을 고칠 수 있어요.",
                           "Tap a row to edit that day's entry."))
                        .janjanBody(12)
                        .foregroundStyle(Color.muted)
                }

                ForEach(Array(past)) { record in
                    Button {
                        pendingEditDay = EditingDay(date: record.date)
                    } label: {
                    HStack(spacing: CGFloat(JanjanSpacing.s)) {
                        Circle()
                            .fill(Color.mood(record.moodScore))
                            .frame(width: 18, height: 18)
                        Text(dayText(record.date))
                            .janjanBody(13)
                            .foregroundStyle(Color.ink2)
                            .monospacedDigit()
                        Text(record.note ?? CheckIn.Mood(record.moodScore).label(JanjanLanguage.current))
                            .janjanBody(13)
                            .foregroundStyle(Color.muted)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.muted)
                    }
                    // 점과 글자만 있는 줄이라 그냥 두면 어디를 눌러야 할지
                    // 모른다. 줄 전체가 손가락 자리가 되게 한다.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: JanjanLanguage.current.localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }

    // MARK: - 저장

    private func saveMood(_ score: Int) {
        let saved = CheckInRecorder.recordMood(score: score, on: viewedDay, in: context)
        save()

        // 기분이 이어져 낮으면 카드를 조용히 올린다. 기록은 이미 저장됐다.
        //
        // @Query 는 이번 렌더에 아직 방금 값을 담고 있지 않을 수 있어서,
        // 오늘 줄만 저장한 값으로 갈아 끼우고 센다. 그러지 않으면 사흘째 −3 을 고른
        // 바로 그 순간에는 카드가 안 뜨고 다음에 화면을 다시 열어야 뜬다.
        var checkIns = checkInRecords
            .filter { !calendar.isDate($0.date, inSameDayAs: viewedDay) }
            .map(\.core)
        checkIns.append(saved.core)

        guard !isDayEditor else { return }
        if let reason = SafetyTrigger.reason(forCheckIns: checkIns, endingAt: viewedDay) {
            safetyReason = SafetyReason(reason: reason)
        }
    }

    private func saveSymptom(symptomID: String, severity: Int, note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = SymptomEntry(
            symptomID: symptomID,
            severity: severity,
            startedAt: symptomTimestamp,
            note: trimmed.isEmpty ? nil : trimmed,
            source: .phone
        )
        context.insert(SymptomEntryRecord.make(from: entry))
        save()

        // 지난 날을 고치는 중에는 안전 카드를 올리지 않는다. 한 달 전 기록을
        // 정리하다가 위기 안내가 튀어나오면 지금의 상태를 잘못 말하는 셈이다.
        guard !isDayEditor else { return }
        if let reason = SafetyTrigger.reason(forSavedSymptomID: symptomID) {
            safetyReason = SafetyReason(reason: reason)
        }
    }

    /// 지난 날에 남기는 증상의 시각. 그날 정오에 둔다 - 몇 시였는지는 알 수
    /// 없고, 자정에 두면 시간대에 따라 전날로 넘어간다.
    private var symptomTimestamp: Date {
        // 한 달의 흐름에서 **오늘** 칸을 눌러 들어와도 이 화면은 고치기
        // 모드다. 그때까지 정오로 박으면 오전에 남긴 증상이 아직 오지 않은
        // 시각으로 저장된다(QA 2026-09-19). 오늘이면 지금이다.
        guard isDayEditor, !calendar.isDateInToday(viewedDay) else { return Date() }
        return calendar.date(
            bySettingHour: 12, minute: 0, second: 0, of: viewedDay
        ) ?? viewedDay
    }

    /// 고치기 화면의 제목. "9월 12일 금요일".
    private var dayTitleText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: JanjanLanguage.current.localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("MMMMdEEE")
        return formatter.string(from: viewedDay)
    }

    private func toggle(_ wordID: String, in record: CheckInRecord) {
        if let index = record.emotionWords.firstIndex(of: wordID) {
            record.emotionWords.remove(at: index)
        } else {
            record.emotionWords.append(wordID)
        }
        touch(record)
    }

    private func toggleActivity(_ tagID: String, in record: CheckInRecord) {
        if let index = record.activities.firstIndex(of: tagID) {
            record.activities.remove(at: index)
        } else {
            record.activities.append(tagID)
        }
        touch(record)
    }

    private func adjustSleep(_ record: CheckInRecord, by minutes: Int) {
        let current = record.sleepMinutes ?? 7 * 60
        let next = current + minutes
        // 0 아래로 내려가면 "안 적음" 으로 되돌린다. 음수 수면은 없다.
        record.sleepMinutes = next <= 0 ? nil : min(next, 24 * 60)
        touch(record)
    }

    private func sleepText(_ record: CheckInRecord) -> String {
        guard let minutes = record.sleepMinutes else { return t("안 적음", "Not set") }
        let hours = minutes / 60
        let rest = minutes % 60
        if JanjanLanguage.current == .english {
            return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
        }
        return rest == 0 ? "\(hours)시간" : "\(hours)시간 \(rest)분"
    }

    // MARK: - 묶기

    /// 옵셔널 문자열 칸을 TextField 에 이어 준다. 비우면 nil 로 되돌린다 —
    /// 빈 문자열과 "안 적음" 을 저장소에서 구별하기 위해서다.
    private func text(
        _ record: CheckInRecord,
        _ keyPath: ReferenceWritableKeyPath<CheckInRecord, String?>
    ) -> Binding<String> {
        Binding(
            get: { record[keyPath: keyPath] ?? "" },
            set: {
                record[keyPath: keyPath] = $0.isEmpty ? nil : $0
                touch(record)
            }
        )
    }

    private func optionalInt(
        _ record: CheckInRecord,
        _ keyPath: ReferenceWritableKeyPath<CheckInRecord, Int?>
    ) -> Binding<Int?> {
        Binding(
            get: { record[keyPath: keyPath] },
            set: {
                record[keyPath: keyPath] = $0
                touch(record)
            }
        )
    }

    private func delete(_ entry: SymptomEntryRecord) {
        context.delete(entry)
        pendingSymptomDeletion = nil
        save()
    }

    /// 마지막으로 손댄 시각과 저장.
    ///
    /// 자동 저장에 기대지 않고 여기서 직접 쓴다. 이 화면은 "저장 버튼이 없다" 고
    /// 약속해 놓았는데, 자동 저장은 즉시가 아니라 잠시 뒤에 몰아서 일어난다.
    /// 감정 단어를 누르고 앱이 강제로 내려가면 그 사이의 편집이 조용히 사라진다.
    private func touch(_ record: CheckInRecord) {
        record.updatedAt = Date()
        save()
    }

    private func save() {
        try? context.save()
    }
}

/// 증상을 골라 세기를 정하는 시트.
///
/// 진단하지 않는다. 카탈로그의 일상어 항목과 0–10 세기만 받는다(설계 12절).
/// 한 번에 여러 증상을 골라 같은 세기로 저장할 수 있다(사용자 요청 2026-09-19).
private struct SymptomEntrySheet: View {

    let onSave: (String, Int, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedIDs: Set<String> = []
    @State private var severity = 5
    @State private var note = ""
    @FocusState private var isEditingNote: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                    ForEach(Catalogs.symptoms.groups) { group in
                        groupCard(group)
                    }

                    if !selectedIDs.isEmpty {
                        severityCard
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
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(TapGesture().onEnded { isEditingNote = false })
            .navigationTitle(t("증상 남기기", "Log a symptom"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(t("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Color.ink)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(t("완료", "Done")) { isEditingNote = false }
                        .foregroundStyle(Color.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("저장", "Save")) {
                        // 카탈로그 순서대로 저장해 목록 순서가 화면 순서와 같게 한다.
                        for group in Catalogs.symptoms.groups {
                            for item in Catalogs.symptoms.symptoms(inGroup: group.id)
                            where selectedIDs.contains(item.id) {
                                onSave(item.id, severity, note)
                            }
                        }
                        dismiss()
                    }
                    .foregroundStyle(selectedIDs.isEmpty ? Color.muted : Color.ink)
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    private func groupCard(_ group: SymptomGroup) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(group.name(JanjanLanguage.current))
                    .janjanBody(13, weight: .medium)
                    .foregroundStyle(Color.muted)

                FlowRow(spacing: CGFloat(JanjanSpacing.xs)) {
                    ForEach(Catalogs.symptoms.symptoms(inGroup: group.id)) { item in
                        let isOn = selectedIDs.contains(item.id)
                        Button {
                            if isOn {
                                selectedIDs.remove(item.id)
                            } else {
                                selectedIDs.insert(item.id)
                            }
                        } label: {
                            PillChip(
                                text: item.name(JanjanLanguage.current),
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

    private var severityCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(t("얼마나 심했어요?", "How severe was it?"))
                    .janjanBody(15, weight: .medium)
                    .foregroundStyle(Color.ink)

                if selectedIDs.count > 1 {
                    Text(t(
                        "고른 증상 \(selectedIDs.count)개가 모두 이 세기로 저장돼요. 하나만 다르면 저장 후 따로 남겨 주세요.",
                        "All \(selectedIDs.count) selected symptoms are saved with this severity. Log one separately if it differs."
                    ))
                        .janjanBody(12)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                CountStepper(
                    text: t(
                        "세기 \(severity) / \(SymptomEntry.severityRange.upperBound)",
                        "Severity \(severity) / \(SymptomEntry.severityRange.upperBound)"
                    ),
                    decreaseLabelKo: t("세기 줄이기", "Decrease severity"),
                    increaseLabelKo: t("세기 늘리기", "Increase severity"),
                    onDecrease: { severity = max(severity - 1, SymptomEntry.severityRange.lowerBound) },
                    onIncrease: { severity = min(severity + 1, SymptomEntry.severityRange.upperBound) }
                )

                TextField(t("덧붙일 말 (선택)", "Add a note (optional)"), text: $note, axis: .vertical)
                    .focused($isEditingNote)
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
}

/// 칩을 줄바꿈해 흘려 놓는 아주 작은 레이아웃.
/// iOS 16+ 의 Layout 프로토콜을 쓴다 — 외부 패키지를 들이지 않기 위해.
struct FlowRow: Layout {

    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var origin = CGPoint.zero
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > 0, origin.x + size.width > maxWidth {
                origin.x = 0
                totalHeight += lineHeight + spacing
                lineHeight = 0
            }
            origin.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        totalHeight += lineHeight
        return CGSize(width: maxWidth == .infinity ? origin.x : maxWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

#Preview {
    DiaryView()
        .modelContainer(for: JanjanSchema.allModels, inMemory: true)
}
