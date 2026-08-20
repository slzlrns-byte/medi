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

    @Environment(\.modelContext) private var context

    @Query(sort: \CheckInRecord.date, order: .reverse) private var checkInRecords: [CheckInRecord]
    @Query(sort: \SymptomEntryRecord.startedAt, order: .reverse)
    private var symptomRecords: [SymptomEntryRecord]

    @State private var isExpanded = false
    @State private var isShowingSymptomSheet = false
    @State private var safetyReason: SafetyReason?

    /// 시트에 넘길 때 Identifiable 이 필요해 감싼다.
    private struct SafetyReason: Identifiable {
        let id = UUID()
        let reason: SafetyTrigger.Reason
    }

    private var today: Date { Date() }
    private var calendar: Calendar { .current }

    private var todayRecord: CheckInRecord? {
        checkInRecords.first { calendar.isDate($0.date, inSameDayAs: today) }
    }

    private var todaysSymptoms: [SymptomEntryRecord] {
        symptomRecords.filter { calendar.isDate($0.startedAt, inSameDayAs: today) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
                    moodCard

                    if let record = todayRecord {
                        noteCard(record)
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
                    questionCard
                    historyCard
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.bottom, CGFloat(JanjanSpacing.xxl))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle("기록")
            .sheet(isPresented: $isShowingSymptomSheet) {
                SymptomEntrySheet { symptomID, severity, note in
                    saveSymptom(symptomID: symptomID, severity: severity, note: note)
                }
            }
            .sheet(item: $safetyReason) { _ in
                SafetyCardView()
            }
        }
    }

    // MARK: - 1층

    private var moodCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("지금 기분은 어떠세요?")
                    .font(JanjanFont.display(22))
                    .foregroundStyle(Color.ink)

                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    ForEach(JanjanMood.scores, id: \.self) { score in
                        moodDot(score)
                    }
                }

                if let record = todayRecord {
                    Text(JanjanMood.label(forScore: record.moodScore))
                        .font(JanjanFont.body(14, weight: .medium))
                        .foregroundStyle(Color.ink2)
                } else {
                    Text("하나만 골라도 완전한 기록이에요.")
                        .font(JanjanFont.body(13))
                        .foregroundStyle(Color.muted)
                }
            }
        }
    }

    private func moodDot(_ score: Int) -> some View {
        let isChosen = todayRecord?.moodScore == score
        return Button {
            saveMood(score)
        } label: {
            Circle()
                .fill(Color.mood(score))
                .frame(width: 38, height: 38)
                .overlay {
                    Circle()
                        .strokeBorder(Color.ink, lineWidth: isChosen ? 2 : 0)
                        .padding(-3)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(JanjanMood.label(forScore: score)))
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : [.isButton])
    }

    private func noteCard(_ record: CheckInRecord) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text("한 줄 남길까요?")
                    .font(JanjanFont.body(15, weight: .medium))
                    .foregroundStyle(Color.ink)
                TextField("", text: text(record, \.note), axis: .vertical)
                    .font(JanjanFont.body(15))
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

    private var expandButton: some View {
        WhitePillButton(
            title: isExpanded ? "접기" : "더 남기기",
            systemImage: isExpanded ? "chevron.up" : "chevron.down"
        ) {
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
        }
    }

    // MARK: - 2층

    private func emotionWordCard(_ record: CheckInRecord) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("어떤 마음이었어요?")
                    .font(JanjanFont.body(15, weight: .medium))
                    .foregroundStyle(Color.ink)

                // 좋은/나쁜을 색으로 편 가르지 않는다. 전부 같은 회색 칩.
                FlowRow(spacing: CGFloat(JanjanSpacing.xs)) {
                    ForEach(Catalogs.emotions.words) { word in
                        let isOn = record.emotionWords.contains(word.id)
                        Button {
                            toggle(word.id, in: record)
                        } label: {
                            PillChip(
                                text: word.nameKo,
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
                scaleRow("기운", value: optionalInt(record, \.energy))
                scaleRow("불안", value: optionalInt(record, \.anxiety))
            }
        }
    }

    /// 1~5 다섯 칸. 고르지 않은 상태로 되돌릴 수 있게 고른 칸을 다시 누르면 지워진다.
    private func scaleRow(_ title: String, value: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
            HStack {
                Text(title)
                    .font(JanjanFont.body(15, weight: .medium))
                    .foregroundStyle(Color.ink)
                Spacer()
                if value.wrappedValue == nil {
                    Text("안 적음")
                        .font(JanjanFont.body(12))
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
                Text("잠은 어땠어요?")
                    .font(JanjanFont.body(15, weight: .medium))
                    .foregroundStyle(Color.ink)

                CountStepper(
                    text: sleepText(record),
                    decreaseLabelKo: "잔 시간 줄이기",
                    increaseLabelKo: "잔 시간 늘리기",
                    onDecrease: { adjustSleep(record, by: -30) },
                    onIncrease: { adjustSleep(record, by: 30) }
                )

                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    ForEach(CheckIn.SleepQuality.allCases, id: \.self) { quality in
                        TogglePill(
                            text: quality.labelKo,
                            isOn: record.sleepQualityRaw == quality.rawValue
                        ) {
                            record.sleepQualityRaw =
                                (record.sleepQualityRaw == quality.rawValue) ? nil : quality.rawValue
                            touch(record)
                        }
                    }
                }

                TogglePill(text: "꿈을 꿨어요", isOn: record.dreamed == true) {
                    record.dreamed = (record.dreamed == true) ? nil : true
                    touch(record)
                }
            }
        }
    }

    private func activityCard(_ record: CheckInRecord) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("무엇을 했어요?")
                    .font(JanjanFont.body(15, weight: .medium))
                    .foregroundStyle(Color.ink)

                FlowRow(spacing: CGFloat(JanjanSpacing.xs)) {
                    ForEach(ActivityTag.presets) { tag in
                        let isOn = record.activities.contains(tag.id)
                        Button {
                            toggleActivity(tag.id, in: record)
                        } label: {
                            PillChip(
                                text: tag.nameKo,
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
                Text("더 쓰고 싶으면")
                    .font(JanjanFont.body(15, weight: .medium))
                    .foregroundStyle(Color.ink)

                TextEditor(text: text(record, \.longText))
                    .font(JanjanFont.body(15))
                    .foregroundStyle(Color.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(CGFloat(JanjanSpacing.xs))
                    .background(
                        RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.row), style: .continuous)
                            .fill(Color.janjan(.surface2))
                    )

                Text("길이 제한은 없어요.")
                    .font(JanjanFont.body(12))
                    .foregroundStyle(Color.muted)
            }
        }
    }

    // MARK: - 증상

    private var symptomCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("증상")
                    .font(JanjanFont.display(20))
                    .foregroundStyle(Color.ink)

                if todaysSymptoms.isEmpty {
                    Text("오늘 남긴 증상이 없어요.")
                        .font(JanjanFont.body(13))
                        .foregroundStyle(Color.muted)
                } else {
                    ForEach(todaysSymptoms) { entry in
                        symptomRow(entry)
                    }
                }

                WhitePillButton(title: "증상 남기기", systemImage: "plus") {
                    isShowingSymptomSheet = true
                }
                .padding(.top, CGFloat(JanjanSpacing.xxs))
            }
        }
    }

    private func symptomRow(_ entry: SymptomEntryRecord) -> some View {
        HStack(spacing: CGFloat(JanjanSpacing.xs)) {
            Text(Catalogs.symptoms.symptom(id: entry.symptomID)?.nameKo ?? entry.symptomID)
                .font(JanjanFont.body(15))
                .foregroundStyle(Color.ink2)
            PillChip(text: "세기 \(entry.severity)")
            Spacer(minLength: 0)
            Button {
                context.delete(entry)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("이 증상 기록 지우기"))
        }
    }

    // MARK: - 질문과 지난 기록

    private var questionCard: some View {
        let card = Catalogs.questions.card(for: today)
        return JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text("오늘의 질문")
                    .font(JanjanFont.body(12, weight: .medium))
                    .foregroundStyle(Color.muted)
                Text(card?.textKo ?? "오늘은 그냥 여기까지여도 괜찮아요.")
                    .font(JanjanFont.display(19))
                    .foregroundStyle(Color.ink)
                    .lineSpacing(3)
            }
        }
    }

    /// 지난 2주. 숫자도 그래프도 없이 점과 글자만 — 되돌아보기지 평가가 아니다.
    private var historyCard: some View {
        let past = checkInRecords
            .filter { !calendar.isDate($0.date, inSameDayAs: today) }
            .prefix(14)

        return JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("지난 기록")
                    .font(JanjanFont.display(20))
                    .foregroundStyle(Color.ink)

                if past.isEmpty {
                    Text("아직 지난 기록이 없어요.")
                        .font(JanjanFont.body(13))
                        .foregroundStyle(Color.muted)
                }

                ForEach(Array(past)) { record in
                    HStack(spacing: CGFloat(JanjanSpacing.s)) {
                        Circle()
                            .fill(Color.mood(record.moodScore))
                            .frame(width: 18, height: 18)
                        Text(dayText(record.date))
                            .font(JanjanFont.body(13))
                            .foregroundStyle(Color.ink2)
                            .monospacedDigit()
                        Text(record.note ?? JanjanMood.label(forScore: record.moodScore))
                            .font(JanjanFont.body(13))
                            .foregroundStyle(Color.muted)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }

    // MARK: - 저장

    private func saveMood(_ score: Int) {
        let saved = CheckInRecorder.recordMood(score: score, on: today, in: context)
        save()

        // 기분이 이어져 낮으면 카드를 조용히 올린다. 기록은 이미 저장됐다.
        //
        // @Query 는 이번 렌더에 아직 방금 값을 담고 있지 않을 수 있어서,
        // 오늘 줄만 저장한 값으로 갈아 끼우고 센다. 그러지 않으면 사흘째 −3 을 고른
        // 바로 그 순간에는 카드가 안 뜨고 다음에 화면을 다시 열어야 뜬다.
        var checkIns = checkInRecords
            .filter { !calendar.isDate($0.date, inSameDayAs: today) }
            .map(\.core)
        checkIns.append(saved.core)

        if let reason = SafetyTrigger.reason(forCheckIns: checkIns, endingAt: today) {
            safetyReason = SafetyReason(reason: reason)
        }
    }

    private func saveSymptom(symptomID: String, severity: Int, note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = SymptomEntry(
            symptomID: symptomID,
            severity: severity,
            startedAt: Date(),
            note: trimmed.isEmpty ? nil : trimmed,
            source: .phone
        )
        context.insert(SymptomEntryRecord.make(from: entry))
        save()

        if let reason = SafetyTrigger.reason(forSavedSymptomID: symptomID) {
            safetyReason = SafetyReason(reason: reason)
        }
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
        guard let minutes = record.sleepMinutes else { return "안 적음" }
        let hours = minutes / 60
        let rest = minutes % 60
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

    /// 마지막으로 손댄 시각. 같은 날 여러 번 고쳤을 때 어느 것이 진실인지 가른다.
    private func touch(_ record: CheckInRecord) {
        record.updatedAt = Date()
    }

    private func save() {
        try? context.save()
    }
}

/// 증상 하나를 고르고 세기를 정하는 시트.
///
/// 진단하지 않는다. 카탈로그의 일상어 항목과 0–10 세기만 받는다(설계 12절).
private struct SymptomEntrySheet: View {

    let onSave: (String, Int, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: String?
    @State private var severity = 5
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                    ForEach(Catalogs.symptoms.groups) { group in
                        groupCard(group)
                    }

                    if selectedID != nil {
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
            .navigationTitle("증상 남기기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(Color.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") {
                        if let selectedID {
                            onSave(selectedID, severity, note)
                        }
                        dismiss()
                    }
                    .foregroundStyle(selectedID == nil ? Color.muted : Color.ink)
                    .disabled(selectedID == nil)
                }
            }
        }
    }

    private func groupCard(_ group: SymptomGroup) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(group.nameKo)
                    .font(JanjanFont.body(13, weight: .medium))
                    .foregroundStyle(Color.muted)

                FlowRow(spacing: CGFloat(JanjanSpacing.xs)) {
                    ForEach(Catalogs.symptoms.symptoms(inGroup: group.id)) { item in
                        let isOn = selectedID == item.id
                        Button {
                            selectedID = isOn ? nil : item.id
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

    private var severityCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("얼마나 심했어요?")
                    .font(JanjanFont.body(15, weight: .medium))
                    .foregroundStyle(Color.ink)

                CountStepper(
                    text: "세기 \(severity) / \(SymptomEntry.severityRange.upperBound)",
                    decreaseLabelKo: "세기 줄이기",
                    increaseLabelKo: "세기 늘리기",
                    onDecrease: { severity = max(severity - 1, SymptomEntry.severityRange.lowerBound) },
                    onIncrease: { severity = min(severity + 1, SymptomEntry.severityRange.upperBound) }
                )

                TextField("덧붙일 말 (선택)", text: $note, axis: .vertical)
                    .font(JanjanFont.body(15))
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
