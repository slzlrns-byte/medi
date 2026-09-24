import Foundation

/// 리포트의 "이번 달의 물결" — 한 달치 기분 색 달력.
///
/// 계획·재고와 같은 원칙을 쓴다. **저장하지 않는다.** 매번 체크인에서 다시 만든다.
/// 지난 기록을 고치면 다음에 열 때 그 색이 바뀌어 있다.
///
/// 숫자·평균·추세 같은 해석은 여기서 만들지 않는다. 색만 돌려주고 해석은 보는
/// 사람이 한다 — "좋아져야 한다" 는 압박이 생기는 순간 이 그림은 기록을 막는
/// 그림이 된다.
public struct MonthWave: Hashable, Sendable {

    public struct DayCell: Hashable, Sendable {
        public let day: Int
        /// 그날의 기분(-3~3). 기록이 없으면 nil.
        public let moodScore: Int?

        public init(day: Int, moodScore: Int?) {
            self.day = day
            self.moodScore = moodScore
        }
    }

    public let year: Int
    public let month: Int
    /// 1일 앞에 두는 빈 칸 수. **일요일 시작으로 못 박는다.** 화면 머리글이
    /// 일·월·화… 순서라, 사용자 달력 설정을 따라가면 칸과 머리글이 어긋난다.
    public let leadingBlanks: Int
    public let days: [DayCell]

    public init(year: Int, month: Int, leadingBlanks: Int, days: [DayCell]) {
        self.year = year
        self.month = month
        self.leadingBlanks = leadingBlanks
        self.days = days
    }

    /// `moment` 가 속한 달의 물결.
    public static func make(
        containing moment: Date,
        checkIns: [CheckIn],
        calendar: Calendar = .current
    ) -> MonthWave {
        let components = calendar.dateComponents([.year, .month], from: moment)
        guard
            let year = components.year,
            let month = components.month,
            let firstDay = calendar.date(from: components),
            let dayRange = calendar.range(of: .day, in: .month, for: firstDay)
        else {
            return MonthWave(year: 0, month: 0, leadingBlanks: 0, days: [])
        }

        // 같은 날 기록이 여럿이면 마지막으로 고친 것을 쓴다.
        var latestByDay: [Int: CheckIn] = [:]
        for checkIn in checkIns
        where calendar.isDate(checkIn.date, equalTo: firstDay, toGranularity: .month) {
            let day = calendar.component(.day, from: checkIn.date)
            if let kept = latestByDay[day], kept.updatedAt >= checkIn.updatedAt { continue }
            latestByDay[day] = checkIn
        }

        // weekday 는 1 이 일요일이다.
        let weekdayOfFirst = calendar.component(.weekday, from: firstDay)

        return MonthWave(
            year: year,
            month: month,
            leadingBlanks: weekdayOfFirst - 1,
            days: dayRange.map { DayCell(day: $0, moodScore: latestByDay[$0]?.mood.score) }
        )
    }
}
