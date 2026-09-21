import Foundation

/// 진료 준비의 "패턴 보기" — 최근 몇 주의 기분·복약·수면을 날짜로 나란히 놓는다.
///
/// 다른 계산기와 같은 원칙을 쓴다. **저장하지 않고**, 매번 기록에서 다시 만든다.
/// 그리고 **해석하지 않는다.** 상관·평균·추세 문장은 만들지 않는다 — 세 줄을
/// 같은 눈금에 올려놓기만 하고, 무엇이 겹치는지는 보는 사람과 진료실이 읽는다.
public struct PatternTimeline: Hashable, Sendable {

    /// 하루치. 세 줄이 같은 열을 쓴다.
    public struct Day: Hashable, Sendable {
        public let date: Date
        /// 그날의 기분(-3~3). 기록이 없으면 nil.
        public let moodScore: Int?
        /// 예정된 복용 항목 수. 0 이면 그날은 계획이 없던 날이다.
        public let scheduledCount: Int
        /// 그중 "복용함" 으로 답한 수.
        public let takenCount: Int
        /// 수면 분. 기록이 없으면 nil.
        public let sleepMinutes: Int?

        public init(
            date: Date,
            moodScore: Int?,
            scheduledCount: Int,
            takenCount: Int,
            sleepMinutes: Int?
        ) {
            self.date = date
            self.moodScore = moodScore
            self.scheduledCount = scheduledCount
            self.takenCount = takenCount
            self.sleepMinutes = sleepMinutes
        }

        /// 복약 줄의 세 가지 모양을 정하는 비율. 계획이 없던 날은 nil.
        public var takenFraction: Double? {
            guard scheduledCount > 0 else { return nil }
            return Double(takenCount) / Double(scheduledCount)
        }
    }

    /// 오래된 날 → 오늘 순서.
    public let days: [Day]

    public init(days: [Day]) {
        self.days = days
    }

    /// `endingAt` 이 속한 날로 끝나는 `dayCount` 일치.
    ///
    /// 복약은 하루 계획(DayPlan)을 그날그날 다시 만들어 센다 — 답하지 않은
    /// 시간대는 기록(DoseEvent)에 줄이 없어서, 기록만 세면 "안 답한 날" 이
    /// "계획이 없던 날" 과 구별되지 않는다.
    public static func make(
        dayCount: Int,
        endingAt end: Date,
        checkIns: [CheckIn],
        schedules: [Schedule],
        medications: [Medication],
        doseEvents: [DoseEvent],
        calendar: Calendar = .current
    ) -> PatternTimeline {
        guard dayCount > 0 else { return PatternTimeline(days: []) }
        let endDay = calendar.startOfDay(for: end)

        // 같은 날 체크인이 여럿이면 마지막으로 고친 것을 쓴다(MonthWave 와 같은 규칙).
        var latestByDay: [Date: CheckIn] = [:]
        for checkIn in checkIns {
            let day = calendar.startOfDay(for: checkIn.date)
            if let kept = latestByDay[day], kept.updatedAt >= checkIn.updatedAt { continue }
            latestByDay[day] = checkIn
        }

        var days: [Day] = []
        for offset in stride(from: dayCount - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: endDay) else { continue }
            // 중단한 약도 **중단하기 전의 날** 에는 복용 중이었다.
            // `DayPlan` 은 지금 상태만 보므로, 그대로 쓰면 약 하나를 끊는
            // 순간 지난 4주에서 그 약이 통째로 사라져 그래프가 갑자기 꽉
            // 찬다 - 저녁 약을 2주 내내 건너뛴 사람이 그 약을 끊으면 지난
            // 2주가 100% 로 보였다(QA 2026-09-21). "기록 없이 지나간
            // 시간대" 가 이미 쓰는 되살리기를 여기에도 쓴다.
            let dayMedications = medications.map { medication -> Medication in
                guard medication.status == .stopped,
                      let stoppedAt = medication.stoppedAt,
                      stoppedAt > date else { return medication }
                var revived = medication
                revived.status = .active
                return revived
            }
            let lines = DayPlan.slots(
                on: date,
                schedules: schedules,
                medications: dayMedications,
                doseEvents: doseEvents,
                calendar: calendar
            )
            let entries = lines.flatMap(\.entries)
            let checkIn = latestByDay[date]
            days.append(Day(
                date: date,
                moodScore: checkIn?.mood.score,
                scheduledCount: entries.count,
                takenCount: entries.filter { $0.status == .taken }.count,
                sleepMinutes: checkIn?.sleepMinutes
            ))
        }
        return PatternTimeline(days: days)
    }
}
