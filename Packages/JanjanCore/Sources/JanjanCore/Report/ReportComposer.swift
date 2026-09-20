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
    /// 이 장이 쓰인 언어. 내보내는 파일 이름도 이것을 따른다 - 본문은
    /// 영어인데 파일 이름만 한국어면 첨부해 보낼 때 섞인다(QA 2026-09-19).
    public let language: JanjanLanguage

    public init(
        titleKo: String,
        periodKo: String,
        lines: [Line],
        disclaimerKo: String,
        language: JanjanLanguage = .standard
    ) {
        self.titleKo = titleKo
        self.periodKo = periodKo
        self.lines = lines
        self.disclaimerKo = disclaimerKo
        self.language = language
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
        /// 주차별 구역을 넣을지. 패턴 보기(Pro)가 파는 것이 이 시계열이라
        /// 무료에서는 구역 자체를 만들지 않는다 - `nextVisit` 과 같은 이유다.
        weeklyBreakdown: Bool = false,
        symptomCatalog: SymptomCatalog = Catalogs.symptoms,
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
        lines.append(contentsOf: asNeededLines(
            medications: medications,
            doseEvents: doseEvents,
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
        if weeklyBreakdown {
            lines.append(contentsOf: weeklyLines(
                checkIns: checkIns,
                symptomEntries: symptomEntries,
                from: start,
                to: end,
                catalog: symptomCatalog,
                language: language,
                calendar: calendar
            ))
        }
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
            disclaimerKo: Janjan.medicalDisclaimer(language),
            language: language
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

    /// 필요시(응급) 복용. 언제 · 몇 번 썼는지만 센다 — 응급약 사용 빈도는 의사가
    /// 실제로 묻는 것이지만, "자주" 같은 해석은 붙이지 않는다. 기록 없으면 구역도 없다.
    private static func asNeededLines(
        medications: [Medication],
        doseEvents: [DoseEvent],
        from start: Date,
        to end: Date,
        language: JanjanLanguage,
        calendar: Calendar
    ) -> [ReportContent.Line] {

        let en = language == .english
        var lines: [ReportContent.Line] = []

        for medication in medications {
            let taken = doseEvents
                .filter {
                    $0.medicationID == medication.id
                        && $0.kind == .asNeeded
                        && $0.status == .taken
                        && $0.effectiveDate >= start && $0.effectiveDate <= end
                }
                .sorted { $0.effectiveDate < $1.effectiveDate }
            guard !taken.isEmpty else { continue }

            // 날짜별로 묶는다: "9/3 · 9/7 2회 · 9/9".
            var dayCounts: [(day: Date, count: Int)] = []
            for event in taken {
                let day = calendar.startOfDay(for: event.effectiveDate)
                if let last = dayCounts.last, last.day == day {
                    dayCounts[dayCounts.count - 1].count += 1
                } else {
                    dayCounts.append((day: day, count: 1))
                }
            }

            if lines.isEmpty {
                lines.append(.init(style: .heading, text: en ? "Rescue (as-needed) doses" : "비상약 복용"))
            }
            let total = taken.count
            lines.append(.init(
                style: .body,
                text: en
                    ? "\(medication.displayTitle) · \(total == 1 ? "once" : "\(total) times")"
                    : "\(medication.displayTitle) · \(total)회"
            ))
            lines.append(.init(
                style: .caption,
                text: dayCounts.map { entry in
                    let day = monthDayText(entry.day, language: language, calendar: calendar)
                    guard entry.count > 1 else { return day }
                    return en ? "\(day) ×\(entry.count)" : "\(day) \(entry.count)회"
                }.joined(separator: " · ")
            ))
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

    /// 주차별 기분·증상 (Pro). 기간을 7일씩 끊어 그 주에 무엇이 몇 번 적혔는지만 옮긴다.
    ///
    /// 위의 기분 구역은 기간 전체를 한 줄로 접는다. 의사가 실제로 묻는 것은
    /// 그 한 줄이 아니라 "언제부터" 인데, 주를 나란히 놓으면 그게 보인다.
    /// 여기서도 세기만 한다 — "2주차에 나빠졌다" 는 만들지 않는다.
    ///
    /// **무료에서는 이 구역이 생기지 않는다.** 패턴 보기(Pro)가 파는 것이
    /// 정확히 이 4주 시계열이라, 여기에 찍어 주면 잠근 문 옆에 문을 하나 더
    /// 내는 셈이다. 잠긴 것을 종이에 알리지도 않는다 - 이 종이는 진료실에서
    /// 의사가 본다.
    private static func weeklyLines(
        checkIns: [CheckIn],
        symptomEntries: [SymptomEntry],
        from start: Date,
        to end: Date,
        catalog: SymptomCatalog,
        language: JanjanLanguage,
        calendar: Calendar
    ) -> [ReportContent.Line] {

        let en = language == .english
        let endDay = calendar.startOfDay(for: end)

        // 주 경계. 마지막 주는 7일이 안 될 수 있어 실제 끝 날짜를 적는다 —
        // 사흘치를 그냥 "4주차" 라고 적으면 옆의 주와 같은 무게로 읽힌다.
        var weeks: [(start: Date, end: Date)] = []
        var cursor = calendar.startOfDay(for: start)
        while cursor <= endDay {
            let last = calendar.date(byAdding: .day, value: 6, to: cursor) ?? cursor
            weeks.append((cursor, min(last, endDay)))
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        // 한 주뿐이면 위의 기분 구역과 같은 말을 한 번 더 하는 것이다.
        guard weeks.count >= 2 else { return [] }

        // 한 주도 빠짐없이 비었으면 구역을 만들지 않는다. "없습니다" 만
        // 늘어선 표는 요약이 아니라 빈 칸 재촉이다.
        let windowEnd = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        let hasAnything =
            checkIns.contains { $0.date >= weeks[0].start && $0.date < windowEnd }
            || symptomEntries.contains { $0.startedAt >= weeks[0].start && $0.startedAt < windowEnd }
        guard hasAnything else { return [] }

        var lines: [ReportContent.Line] = [
            .init(style: .heading, text: en ? "By week" : "주차별")
        ]

        for (index, week) in weeks.enumerated() {
            let dayAfter = calendar.date(byAdding: .day, value: 1, to: week.end) ?? week.end
            let range = "\(monthDayText(week.start, language: language, calendar: calendar))"
                + "–\(monthDayText(week.end, language: language, calendar: calendar))"
            lines.append(.init(
                style: .body,
                text: en ? "Week \(index + 1) · \(range)" : "\(index + 1)주차 · \(range)"
            ))

            let weekCheckIns = checkIns.filter { $0.date >= week.start && $0.date < dayAfter }
            if !weekCheckIns.isEmpty {
                var moodCounts: [Int: Int] = [:]
                for checkIn in weekCheckIns { moodCounts[checkIn.mood.score, default: 0] += 1 }
                // 위의 기분 구역과 **똑같은** 규칙을 쓴다: 평균이 아니라 가장
                // 자주 고른 값, 같은 횟수면 같은 쪽. 한 장 안에서 두 구역이
                // 서로 다른 기분을 적으면 읽는 사람은 둘 다 믿지 않는다.
                if let top = moodCounts.max(by: { lhs, rhs in
                    lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key < rhs.key
                }) {
                    let label = CheckIn.Mood(top.key).label(language)
                    lines.append(.init(
                        style: .caption,
                        text: en
                            ? "Mood \(label) · \(dayCount(top.value, language: language))"
                            : "기분 \(label) · \(top.value)일"
                    ))
                }
            }

            let counts = symptomCounts(
                symptomEntries.filter { $0.startedAt >= week.start && $0.startedAt < dayAfter },
                catalog: catalog,
                language: language
            )
            if !counts.isEmpty {
                lines.append(.init(
                    style: .caption,
                    text: counts
                        .map { en ? "\($0.name) ×\($0.count)" : "\($0.name) \($0.count)회" }
                        .joined(separator: " · ")
                ))
            }

            if weekCheckIns.isEmpty && counts.isEmpty {
                // 빈 주를 지우지 않는다. 기록이 끊긴 주가 있었다는 것도
                // 진료실에서 읽을 것 중 하나다.
                lines.append(.init(
                    style: .caption,
                    text: en ? "No entries this week." : "이 주에는 기록이 없습니다."
                ))
            }
        }
        return lines
    }

    /// 한 주에 적힌 증상을 많이 적힌 차례로 센다. 이름은 카탈로그에서 찾고,
    /// 없으면(사용자가 직접 더한 항목) 적힌 id 를 그대로 쓴다.
    private static func symptomCounts(
        _ entries: [SymptomEntry],
        catalog: SymptomCatalog,
        language: JanjanLanguage
    ) -> [(name: String, count: Int)] {

        var counts: [String: Int] = [:]
        for entry in entries { counts[entry.symptomID, default: 0] += 1 }

        let ranked = counts
            .map { id, count in
                (id: id,
                 count: count,
                 safety: catalog.symptom(id: id)?.isSafetyItem ?? false,
                 name: catalog.symptom(id: id)?.name(language) ?? id)
            }
            // 횟수가 같으면 id 로 갈라 차례를 고정한다 - 같은 기록으로 두 번
            // 뽑은 종이가 서로 달라 보이면 안 된다.
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.id < rhs.id
            }

        var shown = Array(ranked.prefix(weeklySymptomLimit))
        // 자해·자살 생각은 자른 뒤에도 남긴다. 그 한 줄을 보이려고 종이를
        // 만드는 사람이 있는데, 다른 증상이 많았다는 이유로 빠지면 안 된다.
        for item in ranked where item.safety && !shown.contains(where: { $0.id == item.id }) {
            shown.append(item)
        }
        return shown.map { (name: $0.name, count: $0.count) }
    }

    /// 한 주에 적는 증상 수. 더 늘리면 요약이 아니라 목록이 된다.
    private static let weeklySymptomLimit = 4

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
