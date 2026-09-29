import Foundation

/// 용량 변경 전후를 **해석 없이 나란히** 놓는다 (Pro).
///
/// "약 바꾸고 어땠어요?" 는 진료실에서 실제로 받는 질문이다. 이 계산은 그 답의
/// 재료만 만든다 - 변경 전 2주와 후 2주의 기분·수면·증상·꿈을 사실로 세고,
/// 좋아졌다·나빠졌다 같은 말은 어디에도 붙이지 않는다(D12: 계산·권고 없음).
/// 해석은 진료실에서 사람이 한다.
public struct DoseChangeComparison: Hashable, Sendable {

    /// 한쪽 구간(전 또는 후)의 사실들. 적지 않은 항목은 nil - 빈 칸은 빈 칸대로 둔다.
    public struct Window: Hashable, Sendable {
        /// 구간에 실제로 들어간 날수. "후" 구간이 아직 다 차지 않았으면 14보다 작다.
        public let days: Int
        /// 기분을 적은 날수.
        public let moodRecordedDays: Int
        /// 기분 평균(-3.0 ~ +3.0, 소수 한 자리). 기록이 없으면 nil.
        public let moodAverage: Double?
        /// 수면을 적은 날들의 평균 분. 기록이 없으면 nil.
        public let sleepAverageMinutes: Int?
        /// 증상을 기록한 날수(종류 무관, 하루에 여러 건이어도 하루).
        public let symptomDays: Int
        /// 꿈을 꿨다고 적은 날수 · 그중 악몽 날수.
        public let dreamDays: Int
        public let nightmareDays: Int

        public init(
            days: Int,
            moodRecordedDays: Int,
            moodAverage: Double?,
            sleepAverageMinutes: Int?,
            symptomDays: Int,
            dreamDays: Int,
            nightmareDays: Int
        ) {
            self.days = days
            self.moodRecordedDays = moodRecordedDays
            self.moodAverage = moodAverage
            self.sleepAverageMinutes = sleepAverageMinutes
            self.symptomDays = symptomDays
            self.dreamDays = dreamDays
            self.nightmareDays = nightmareDays
        }
    }

    public static let windowDays = 14

    public let change: DoseChange
    /// 변경 날 **전** `windowDays` 일. 변경 당일은 "후" 에 속한다.
    public let before: Window
    /// 변경 당일부터의 `windowDays` 일. 아직 다 지나지 않았으면 오늘까지만 센다.
    public let after: Window

    /// 두 구간 다 아무 기록이 없으면 보여 줄 것이 없다.
    public var hasAnything: Bool {
        before.moodRecordedDays + before.symptomDays + before.dreamDays > 0
            || after.moodRecordedDays + after.symptomDays + after.dreamDays > 0
    }

    public static func make(
        change: DoseChange,
        checkIns: [CheckIn],
        symptomEntries: [SymptomEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DoseChangeComparison {

        let changeDay = calendar.startOfDay(for: change.changedAt)
        let collapsed = CheckIn.collapsedByDay(checkIns, calendar: calendar)

        // 전: [변경일-14, 변경일). 후: [변경일, 변경일+14) 를 오늘까지로 자른다.
        let beforeStart = calendar.date(byAdding: .day, value: -windowDays, to: changeDay) ?? changeDay
        let afterEndFull = calendar.date(byAdding: .day, value: windowDays, to: changeDay) ?? changeDay
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let afterEnd = min(afterEndFull, tomorrow)
        let afterDays = max(0, calendar.dateComponents([.day], from: changeDay, to: afterEnd).day ?? 0)

        func window(from start: Date, to end: Date, days: Int) -> Window {
            let ins = collapsed.filter { $0.date >= start && $0.date < end }
            let moods = ins.map { Double($0.mood.score) }
            let sleeps = ins.compactMap(\.sleepMinutes)
            let symptomDays = Set(
                symptomEntries
                    .filter { $0.startedAt >= start && $0.startedAt < end }
                    .map { calendar.startOfDay(for: $0.startedAt) }
            ).count

            return Window(
                days: days,
                moodRecordedDays: ins.count,
                moodAverage: moods.isEmpty
                    ? nil
                    : (moods.reduce(0, +) / Double(moods.count) * 10).rounded() / 10,
                sleepAverageMinutes: sleeps.isEmpty
                    ? nil
                    : sleeps.reduce(0, +) / sleeps.count,
                symptomDays: symptomDays,
                dreamDays: ins.filter { $0.dreamed == true }.count,
                nightmareDays: ins.filter { $0.nightmare == true }.count
            )
        }

        return DoseChangeComparison(
            change: change,
            before: window(from: beforeStart, to: changeDay, days: windowDays),
            after: window(from: changeDay, to: afterEnd, days: afterDays)
        )
    }

    public init(change: DoseChange, before: Window, after: Window) {
        self.change = change
        self.before = before
        self.after = after
    }

    // MARK: - 표시용 문장 조각

    /// "-0.6" / "+1.2" / "0.0". 부호를 붙여 방향이 글자로 보이게 한다 - 색만으로 말하지 않는다.
    public static func moodText(_ average: Double?) -> String? {
        guard let average else { return nil }
        let sign = average > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", average))"
    }

    /// 421분 → "7시간 1분" / "7h 1m".
    public static func sleepText(_ minutes: Int?, language: JanjanLanguage) -> String? {
        guard let minutes else { return nil }
        let hours = minutes / 60
        let rest = minutes % 60
        if language == .english {
            return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
        }
        return rest == 0 ? "\(hours)시간" : "\(hours)시간 \(rest)분"
    }
}
