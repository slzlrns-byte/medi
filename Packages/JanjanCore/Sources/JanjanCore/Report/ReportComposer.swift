import Foundation

/// 진료에 가져갈 4주 요약의 **내용**. 종이에 어떻게 앉힐지는 앱이 정한다.
///
/// 글자를 여기서 만드는 이유: PDF 그리는 코드 안에 문장이 섞여 들어가면
/// 말투 규칙(존댓말·이모지 없음·판단하지 않음)을 테스트로 지킬 수 없다.
public struct ReportContent: Hashable, Sendable {

    public struct Line: Hashable, Sendable {

        public enum Style: Hashable, Sendable {
            /// 구역 제목.
            case heading
            /// 본문 한 줄.
            case body
            /// 본문에 딸린 작은 설명.
            case caption
        }

        public let style: Style
        public let text: String

        public init(style: Style, text: String) {
            self.style = style
            self.text = text
        }
    }

    public let titleKo: String
    /// "2026년 7월 24일 – 2026년 8월 20일"
    public let periodKo: String
    public let lines: [Line]
    public let disclaimerKo: String

    public init(titleKo: String, periodKo: String, lines: [Line], disclaimerKo: String) {
        self.titleKo = titleKo
        self.periodKo = periodKo
        self.lines = lines
        self.disclaimerKo = disclaimerKo
    }
}

/// 기록을 4주 요약 한 장으로 접는다.
///
/// 이 파일은 **세기만 한다.** 좋아졌다·나빠졌다·잘 지켰다 같은 말은 한 줄도 만들지 않는다.
/// 해석은 진료실에서 사람이 한다(설계 01절 원칙).
public enum ReportComposer {

    /// 진료 앵커가 없을 때 보는 기간. 복약률과 같은 4주를 쓴다.
    public static let windowDays = 28
    /// 지난 진료가 이보다 오래됐으면 4주로 되돌린다 —
    /// 반년치를 한 장에 접으면 요약이 아니라 목록이 된다.
    public static let maxAnchoredDays = 90

    /// 요약이 보는 기간. 화면(복약률 카드)과 PDF 가 같은 창을 써야 해서 공용이다.
    ///
    /// 지난 진료가 있으면 그날부터 본다 (강점 결정서 1위 — "지난 진료 이후").
    /// 의사가 궁금한 것은 지난 4주가 아니라 마지막으로 본 뒤의 일이기 때문이다.
    public static func window(
        endingAt end: Date,
        lastVisit: Date?,
        calendar: Calendar = .current
    ) -> (start: Date, anchoredToVisit: Bool) {
        let endDay = calendar.startOfDay(for: end)

        if let visit = lastVisit {
            let day = calendar.startOfDay(for: visit)
            if day <= endDay,
               let oldest = calendar.date(byAdding: .day, value: -(maxAnchoredDays - 1), to: endDay),
               day >= oldest {
                return (day, true)
            }
        }
        let start = calendar.date(byAdding: .day, value: -(windowDays - 1), to: endDay) ?? endDay
        return (start, false)
    }

    public static func make(
        endingAt end: Date,
        medications: [Medication],
        schedules: [Schedule],
        doseEvents: [DoseEvent],
        stockEvents: [StockEvent],
        checkIns: [CheckIn],
        medicationNotes: [MedicationNote] = [],
        symptomEntries: [SymptomEntry] = [],
        doseChanges: [DoseChange] = [],
        lastVisit: Date? = nil,
        nextVisit: Date? = nil,
        questionsKo: String = "",
        language: JanjanLanguage = .korean,
        calendar: Calendar = .current
    ) -> ReportContent {

        let endDay = calendar.startOfDay(for: end)
        let (start, anchored) = window(endingAt: end, lastVisit: lastVisit, calendar: calendar)
        let windowLength = (calendar.dateComponents([.day], from: start, to: endDay).day ?? 0) + 1

        // 기기 간 동기화로 같은 날 체크인이 두 줄이 됐어도 하루로 센다.
        let checkIns = CheckIn.collapsedByDay(checkIns, calendar: calendar)

        var lines: [ReportContent.Line] = []
        lines.append(contentsOf: adherenceLines(
            doseEvents: doseEvents, from: start, to: end, language: language
        ))
        lines.append(contentsOf: medicationLines(
            medications: medications,
            schedules: schedules,
            doseEvents: doseEvents,
            stockEvents: stockEvents,
            nextVisit: nextVisit,
            from: start,
            to: end,
            language: language,
            calendar: calendar
        ))
        lines.append(contentsOf: doseChangeLines(
            doseChanges: doseChanges,
            medications: medications,
            from: start,
            to: end,
            language: language,
            calendar: calendar
        ))
        lines.append(contentsOf: moodLines(
            checkIns: checkIns,
            from: start,
            to: end,
            windowLength: windowLength,
            language: language,
            calendar: calendar
        ))
        lines.append(contentsOf: dreamLines(
            checkIns: checkIns, from: start, to: end, language: language, calendar: calendar
        ))
        lines.append(contentsOf: lifestyleLines(
            checkIns: checkIns, from: start, to: end, language: language, calendar: calendar
        ))
        lines.append(contentsOf: noteLines(
            notes: medicationNotes,
            medications: medications,
            symptomEntries: symptomEntries,
            from: start,
            to: end,
            language: language
        ))
        lines.append(contentsOf: questionLines(questionsKo, language: language))

        let title: String
        if language == .english {
            title = anchored
                ? "\(Janjan.appNameEn) · Since the last visit"
                : "\(Janjan.appNameEn) · 4-week summary"
        } else {
            title = anchored
                ? "\(Janjan.appNameKo) · 지난 진료 이후"
                : "\(Janjan.appNameKo) · 4주 요약"
        }

        return ReportContent(
            titleKo: title,
            periodKo: "\(dayText(start, language: language, calendar: calendar)) – \(dayText(endDay, language: language, calendar: calendar))",
            lines: lines,
            disclaimerKo: Janjan.medicalDisclaimer(language)
        )
    }

    // MARK: - 구역

    private static func adherenceLines(
        doseEvents: [DoseEvent],
        from start: Date,
        to end: Date,
        language: JanjanLanguage
    ) -> [ReportContent.Line] {

        let en = language == .english
        var lines: [ReportContent.Line] = [.init(style: .heading, text: en ? "Medication" : "복약")]

        let counted = doseEvents.filter { event in
            event.kind == .scheduled && event.effectiveDate >= start && event.effectiveDate <= end
        }

        guard !counted.isEmpty else {
            lines.append(.init(
                style: .body,
                text: en ? "There is nothing to count in this period." : "이 기간에는 셀 기록이 없습니다."
            ))
            return lines
        }

        let taken = counted.filter { $0.status == .taken }.count
        let skipped = counted.filter { $0.status == .skipped }.count
        let unrecorded = counted.filter { $0.status == .unrecorded }.count

        if let rate = InventoryCalculator.adherenceRate(doseEvents: doseEvents, from: start, to: end) {
            lines.append(.init(
                style: .body,
                text: en ? "Adherence \(percentText(rate))" : "복약률 \(percentText(rate))"
            ))
        }
        lines.append(.init(
            style: .body,
            text: en
                ? "Taken \(taken) · Skipped \(skipped) · Unrecorded \(unrecorded)"
                : "복용 \(taken)회 · 건너뜀 \(skipped)회 · 미기록 \(unrecorded)회"
        ))
        lines.append(.init(
            style: .caption,
            text: en
                ? "Skipped is a choice not to take; unrecorded is a scheduled dose with no answer."
                : "건너뜀은 복용하지 않기로 한 선택이고, 미기록은 답하지 않은 예정분입니다."
        ))
        return lines
    }

    private static func medicationLines(
        medications: [Medication],
        schedules: [Schedule],
        doseEvents: [DoseEvent],
        stockEvents: [StockEvent],
        nextVisit: Date?,
        from start: Date,
        to end: Date,
        language: JanjanLanguage,
        calendar: Calendar
    ) -> [ReportContent.Line] {

        let en = language == .english
        var lines: [ReportContent.Line] = [.init(style: .heading, text: en ? "Medications" : "약")]

        let listed = medications.filter { $0.status == .active }
        guard !listed.isEmpty else {
            lines.append(.init(
                style: .body,
                text: en ? "No medications are registered." : "등록된 약이 없습니다."
            ))
            return lines
        }

        for medication in listed {
            let snapshot = InventoryCalculator.snapshot(
                medicationID: medication.id,
                schedules: schedules,
                stockEvents: stockEvents,
                doseEvents: doseEvents,
                nextVisit: nextVisit,
                asOf: end,
                calendar: calendar
            )

            var parts: [String] = [medication.displayTitle]
            if medication.kind == .asNeeded {
                parts.append(medication.kind.label(language))
            }
            if let rate = InventoryCalculator.adherenceRate(
                doseEvents: doseEvents,
                medicationID: medication.id,
                from: start,
                to: end
            ) {
                parts.append(en ? "adherence \(percentText(rate))" : "복약률 \(percentText(rate))")
            }
            // 재고를 한 번도 세지 않았으면 0정이라고 말하지 않는다.
            if stockEvents.contains(where: { $0.medicationID == medication.id }) {
                parts.append(en
                    ? "\(DecimalQuantity.display(snapshot.remaining)) left"
                    : "남은 개수 \(DecimalQuantity.display(snapshot.remaining))정")
            }
            lines.append(.init(style: .body, text: parts.joined(separator: " · ")))

            if let shortfall = snapshot.shortfallDays, shortfall > 0 {
                lines.append(.init(
                    style: .caption,
                    text: en
                        ? "About \(shortfall) days short before the next visit."
                        : "다음 진료 전 \(shortfall)일 모자랍니다."
                ))
            }
        }
        return lines
    }

    /// "9/3 에스시탈로프람 5mg → 10mg". 적힌 그대로만 옮긴다 — 강점 결정서 D12.
    private static func doseChangeLines(
        doseChanges: [DoseChange],
        medications: [Medication],
        from start: Date,
        to end: Date,
        language: JanjanLanguage,
        calendar: Calendar
    ) -> [ReportContent.Line] {

        let en = language == .english
        let inWindow = doseChanges
            .filter { $0.changedAt >= start && $0.changedAt <= end }
            .sorted { $0.changedAt < $1.changedAt }
        guard !inWindow.isEmpty else { return [] }

        var lines: [ReportContent.Line] = [
            .init(style: .heading, text: en ? "Dose changes" : "용량 변경")
        ]
        for change in inWindow {
            let name = medications.first { $0.id == change.medicationID }?.name
                ?? (en ? "a deleted medication" : "지운 약")
            lines.append(.init(
                style: .body,
                text: "\(monthDayText(change.changedAt, language: language, calendar: calendar)) · \(name) \(change.arrowTextKo)"
            ))
            if let note = change.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                lines.append(.init(style: .caption, text: note))
            }
        }
        return lines
    }

    private static func moodLines(
        checkIns: [CheckIn],
        from start: Date,
        to end: Date,
        windowLength: Int,
        language: JanjanLanguage,
        calendar: Calendar
    ) -> [ReportContent.Line] {

        let en = language == .english
        var lines: [ReportContent.Line] = [.init(style: .heading, text: en ? "Mood" : "기분")]

        let inWindow = checkIns.filter { $0.date >= start && $0.date <= end }
        guard !inWindow.isEmpty else {
            lines.append(.init(
                style: .body,
                text: en ? "No mood entries in this period." : "이 기간에는 기분 기록이 없습니다."
            ))
            return lines
        }

        let days = Set(inWindow.map { calendar.startOfDay(for: $0.date) }).count
        lines.append(.init(
            style: .body,
            text: en ? "Recorded \(days) of \(windowLength) days" : "\(windowLength)일 중 \(days)일 기록"
        ))

        // 가장 자주 고른 값 하나만 적는다. 평균은 −3~+3 을 섞어 놓아 뜻이 흐려진다.
        var counts: [Int: Int] = [:]
        for checkIn in inWindow { counts[checkIn.mood.score, default: 0] += 1 }
        if let top = counts.max(by: { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key < rhs.key
        }) {
            let label = CheckIn.Mood(top.key).label(language)
            lines.append(.init(
                style: .body,
                text: en
                    ? "Most chosen mood: \(label) (\(dayCount(top.value, language: language)))"
                    : "가장 자주 고른 기분: \(label) (\(top.value)일)"
            ))
        }
        return lines
    }

    /// 꿈 (강점 결정서 4위). 척도를 세고 메모를 옮길 뿐, 뜻풀이는 하지 않는다 —
    /// 꿈 해석은 이 앱이 의도적으로 하지 않는 것 목록에 있다.
    private static func dreamLines(
        checkIns: [CheckIn],
        from start: Date,
        to end: Date,
        language: JanjanLanguage,
        calendar: Calendar
    ) -> [ReportContent.Line] {

        let en = language == .english

        let dreamed = checkIns
            .filter { $0.date >= start && $0.date <= end && $0.dreamed == true }
            .sorted { $0.date < $1.date }
        // 꿈 기록이 없으면 구역 자체를 만들지 않는다. "꿈: 없음" 은 빈 칸 재촉이 된다.
        guard !dreamed.isEmpty else { return [] }

        var lines: [ReportContent.Line] = [.init(style: .heading, text: en ? "Dreams" : "꿈")]

        var parts = [en
            ? "Dreams noted on \(dayCount(dreamed.count, language: language))"
            : "꿈을 기록한 날 \(dreamed.count)일"]
        let vivid = dreamed.filter { ($0.dreamVividness ?? 0) >= 3 }.count
        if vivid > 0 {
            parts.append(en ? "very vivid \(dayCount(vivid, language: language))" : "아주 생생함 \(vivid)일")
        }
        let nightmares = dreamed.filter { $0.nightmare == true }.count
        if nightmares > 0 {
            parts.append(en ? "nightmares \(dayCount(nightmares, language: language))" : "악몽 \(nightmares)일")
        }
        lines.append(.init(style: .body, text: parts.joined(separator: " · ")))

        // 메모는 최근 것부터 세 개까지만. 종이 한 장의 자리를 지킨다.
        let noted = dreamed
            .compactMap { checkIn -> (Date, String)? in
                guard let note = checkIn.dreamNote?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !note.isEmpty
                else { return nil }
                return (checkIn.date, note)
            }
            .suffix(3)
        for (date, note) in noted {
            lines.append(.init(
                style: .caption,
                text: "\(monthDayText(date, language: language, calendar: calendar)) · \(note)"
            ))
        }
        return lines
    }

    /// 술·담배 (사용자 결정 2026-09-10). 약과 영향을 주고받을 수 있어 의사가
    /// 진료 때 실제로 묻는 항목이라, 활동 칩 중 이 둘만 일수로 센다.
    /// 세기만 한다 — 줄였다·늘었다·괜찮다 같은 말은 만들지 않는다.
    private static func lifestyleLines(
        checkIns: [CheckIn],
        from start: Date,
        to end: Date,
        language: JanjanLanguage,
        calendar: Calendar
    ) -> [ReportContent.Line] {

        let en = language == .english

        let inWindow = checkIns.filter { $0.date >= start && $0.date <= end }

        func days(withTag id: String) -> Int {
            Set(
                inWindow
                    .filter { $0.activities.contains(id) }
                    .map { calendar.startOfDay(for: $0.date) }
            ).count
        }

        let alcohol = days(withTag: ActivityTag.alcoholID)
        let smoking = days(withTag: ActivityTag.smokingID)

        var parts: [String] = []
        if alcohol > 0 {
            parts.append(en ? "Alcohol on \(dayCount(alcohol, language: language))" : "술 마신 날 \(alcohol)일")
        }
        if smoking > 0 {
            parts.append(en ? "Smoking on \(dayCount(smoking, language: language))" : "담배 피운 날 \(smoking)일")
        }
        // 하나도 없으면 구역 자체를 만들지 않는다. "0일" 은 빈 칸 재촉이 된다.
        guard !parts.isEmpty else { return [] }

        return [
            .init(style: .heading, text: en ? "Lifestyle" : "생활"),
            .init(style: .body, text: parts.joined(separator: " · "))
        ]
    }

    /// 진료에서 들은 것과 실제 기록을 나란히 놓는다.
    ///
    /// 세기만 한다. "약 때문이다" 도 "괜찮아졌다" 도 만들지 않는다 —
    /// 옆에 놓아 주면 해석은 진료실에서 사람이 한다.
    private static func noteLines(
        notes: [MedicationNote],
        medications: [Medication],
        symptomEntries: [SymptomEntry],
        from start: Date,
        to end: Date,
        language: JanjanLanguage
    ) -> [ReportContent.Line] {

        let en = language == .english
        let observations = MedicationNoteDigest.observations(
            notes: notes,
            medications: medications,
            symptomEntries: symptomEntries,
            from: start,
            to: end,
            language: language
        )
        guard !observations.isEmpty else { return [] }

        var lines: [ReportContent.Line] = [
            .init(style: .heading, text: en ? "Notes on medications" : "약에 적어 둔 것")
        ]
        var lastMedication: String?

        for observation in observations {
            if observation.medicationName != lastMedication {
                lines.append(.init(style: .body, text: observation.medicationName))
                lastMedication = observation.medicationName
            }
            lines.append(.init(
                style: .caption,
                text: "\(observation.note.kind.label(language)) · \(MedicationNoteDigest.line(for: observation, language: language))"
            ))
        }

        lines.append(.init(
            style: .caption,
            text: en
                ? "The count is how often that symptom was recorded; it does not name a cause."
                : "옆의 횟수는 그 증상이 기록된 수이고, 원인을 말하지 않습니다."
        ))
        return lines
    }

    private static func questionLines(
        _ questionsKo: String,
        language: JanjanLanguage
    ) -> [ReportContent.Line] {
        let trimmed = questionsKo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var lines: [ReportContent.Line] = [
            .init(style: .heading, text: language == .english ? "Questions for my doctor" : "의사에게 물어볼 것")
        ]
        for raw in trimmed.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { lines.append(.init(style: .body, text: line)) }
        }
        return lines
    }

    // MARK: - 글자

    /// 0.826 → "82%". 올림하지 않는다 — 실제보다 잘 지킨 것처럼 보이면 안 된다.
    static func percentText(_ rate: Decimal) -> String {
        "\(DecimalQuantity.floorToInt(rate * 100))%"
    }

    static func dayText(
        _ date: Date,
        language: JanjanLanguage = .korean,
        calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = language == .english ? "MMMM d, yyyy" : "yyyy년 M월 d일"
        return formatter.string(from: date)
    }

    /// "9월 3일". 기간 안의 날짜라 연도는 머리글이 이미 말했다.
    static func monthDayText(
        _ date: Date,
        language: JanjanLanguage = .korean,
        calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = language == .english ? "MMM d" : "M월 d일"
        return formatter.string(from: date)
    }

    /// "1 day" / "3 days". 한국어는 조수사가 규칙적이라 이 도우미가 필요 없다.
    private static func dayCount(_ count: Int, language: JanjanLanguage) -> String {
        guard language == .english else { return "\(count)일" }
        return count == 1 ? "1 day" : "\(count) days"
    }
}
