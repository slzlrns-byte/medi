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

    /// 요약이 보는 기간. 복약률과 같은 4주를 쓴다.
    public static let windowDays = 28

    public static func make(
        endingAt end: Date,
        medications: [Medication],
        schedules: [Schedule],
        doseEvents: [DoseEvent],
        stockEvents: [StockEvent],
        checkIns: [CheckIn],
        nextVisit: Date? = nil,
        questionsKo: String = "",
        calendar: Calendar = .current
    ) -> ReportContent {

        let endDay = calendar.startOfDay(for: end)
        let start = calendar.date(byAdding: .day, value: -(windowDays - 1), to: endDay) ?? endDay

        var lines: [ReportContent.Line] = []
        lines.append(contentsOf: adherenceLines(doseEvents: doseEvents, from: start, to: end))
        lines.append(contentsOf: medicationLines(
            medications: medications,
            schedules: schedules,
            doseEvents: doseEvents,
            stockEvents: stockEvents,
            nextVisit: nextVisit,
            from: start,
            to: end,
            calendar: calendar
        ))
        lines.append(contentsOf: moodLines(checkIns: checkIns, from: start, to: end, calendar: calendar))
        lines.append(contentsOf: questionLines(questionsKo))

        return ReportContent(
            titleKo: "\(Janjan.appNameKo) · 4주 요약",
            periodKo: "\(dayText(start, calendar: calendar)) – \(dayText(endDay, calendar: calendar))",
            lines: lines,
            disclaimerKo: Janjan.medicalDisclaimerKo
        )
    }

    // MARK: - 구역

    private static func adherenceLines(
        doseEvents: [DoseEvent],
        from start: Date,
        to end: Date
    ) -> [ReportContent.Line] {

        var lines: [ReportContent.Line] = [.init(style: .heading, text: "복약")]

        let counted = doseEvents.filter { event in
            event.kind == .scheduled && event.effectiveDate >= start && event.effectiveDate <= end
        }

        guard !counted.isEmpty else {
            lines.append(.init(style: .body, text: "이 기간에는 셀 기록이 없습니다."))
            return lines
        }

        let taken = counted.filter { $0.status == .taken }.count
        let skipped = counted.filter { $0.status == .skipped }.count
        let unrecorded = counted.filter { $0.status == .unrecorded }.count

        if let rate = InventoryCalculator.adherenceRate(doseEvents: doseEvents, from: start, to: end) {
            lines.append(.init(style: .body, text: "복약률 \(percentText(rate))"))
        }
        lines.append(.init(
            style: .body,
            text: "복용 \(taken)회 · 건너뜀 \(skipped)회 · 미기록 \(unrecorded)회"
        ))
        lines.append(.init(
            style: .caption,
            text: "건너뜀은 복용하지 않기로 한 선택이고, 미기록은 답하지 않은 예정분입니다."
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
        calendar: Calendar
    ) -> [ReportContent.Line] {

        var lines: [ReportContent.Line] = [.init(style: .heading, text: "약")]

        let listed = medications.filter { $0.status == .active }
        guard !listed.isEmpty else {
            lines.append(.init(style: .body, text: "등록된 약이 없습니다."))
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
                parts.append("필요시")
            }
            if let rate = InventoryCalculator.adherenceRate(
                doseEvents: doseEvents,
                medicationID: medication.id,
                from: start,
                to: end
            ) {
                parts.append("복약률 \(percentText(rate))")
            }
            // 재고를 한 번도 세지 않았으면 0정이라고 말하지 않는다.
            if stockEvents.contains(where: { $0.medicationID == medication.id }) {
                parts.append("남은 개수 \(DecimalQuantity.display(snapshot.remaining))정")
            }
            lines.append(.init(style: .body, text: parts.joined(separator: " · ")))

            if let shortfall = snapshot.shortfallDays, shortfall > 0 {
                lines.append(.init(style: .caption, text: "다음 진료 전 \(shortfall)일 모자랍니다."))
            }
        }
        return lines
    }

    private static func moodLines(
        checkIns: [CheckIn],
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> [ReportContent.Line] {

        var lines: [ReportContent.Line] = [.init(style: .heading, text: "기분")]

        let inWindow = checkIns.filter { $0.date >= start && $0.date <= end }
        guard !inWindow.isEmpty else {
            lines.append(.init(style: .body, text: "이 기간에는 기분 기록이 없습니다."))
            return lines
        }

        let days = Set(inWindow.map { calendar.startOfDay(for: $0.date) }).count
        lines.append(.init(style: .body, text: "\(windowDays)일 중 \(days)일 기록"))

        // 가장 자주 고른 값 하나만 적는다. 평균은 −3~+3 을 섞어 놓아 뜻이 흐려진다.
        var counts: [Int: Int] = [:]
        for checkIn in inWindow { counts[checkIn.mood.score, default: 0] += 1 }
        if let top = counts.max(by: { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key < rhs.key
        }) {
            let label = CheckIn.Mood(top.key).labelKo
            lines.append(.init(style: .body, text: "가장 자주 고른 기분: \(label) (\(top.value)일)"))
        }
        return lines
    }

    private static func questionLines(_ questionsKo: String) -> [ReportContent.Line] {
        let trimmed = questionsKo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var lines: [ReportContent.Line] = [.init(style: .heading, text: "의사에게 물어볼 것")]
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

    static func dayText(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy년 M월 d일"
        return formatter.string(from: date)
    }
}
