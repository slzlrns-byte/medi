import Foundation

/// 기록 없이 지나간 정기 시간대를 찾는다.
///
/// "빠트렸다" 고 단정하지 않는다 — 기록이 없다는 사실만 들어 보인다. 재고를 세어
/// 개수가 어긋났을 때, 그 차이를 앱이 임의로 어느 날짜에 배정하면 반드시 틀린다.
/// 대신 이 목록("화요일 아침, 수요일 아침")을 보여 주고 사용자가 고르게 한다.
///
/// 명시적 `미기록(unrecorded)` 사건이 있는 줄은 다시 들지 않는다 — 그것은
/// 사용자가 "기억 안 나요" 라고 이미 답한 것이고, 같은 질문을 반복하면 재촉이 된다.
public enum UnrecordedSlots {

    /// 기록 없는 시간대 한 줄. 같은 시간대에 일부 약만 기록했다면 나머지 약만 담는다.
    public struct Line: Identifiable, Hashable, Sendable {

        public let day: Date
        public let slot: DoseSlot
        /// 이 시간대가 실제로 예정돼 있던 시각.
        public let plannedAt: Date
        /// 아무 기록도 없는 약들.
        public let entries: [DayPlan.Entry]

        public var id: String { "\(slot.storageKey)-\(day.timeIntervalSinceReferenceDate)" }

        public init(day: Date, slot: DoseSlot, plannedAt: Date, entries: [DayPlan.Entry]) {
            self.day = day
            self.slot = slot
            self.plannedAt = plannedAt
            self.entries = entries
        }
    }

    /// 화면에 한 번에 들어 보일 범위의 상한. 이보다 오래된 것은 세지 않는다 —
    /// 이 도구는 "어제오늘 빠트렸나" 를 돕는 것이지 과거를 감사하는 것이 아니다.
    public static let maxLookbackDays = 31

    /// `from`(그 날 전체)부터 `now` 까지, 시각이 이미 지났는데 기록이 하나도 없는 줄.
    ///
    /// - `now` 가 속한 날의 시간대는 예정 시각이 지난 것만 든다. 아직 안 온
    ///   오늘 저녁 약은 빠트린 것이 아니다.
    /// - 상태가 있는 사건(복용함·건너뜀·미기록)이 하나라도 있는 약은 빼고,
    ///   정말 아무 기록도 없는 약만 담는다.
    public static func find(
        from: Date,
        until now: Date,
        schedules: [Schedule],
        medications: [Medication],
        doseEvents: [DoseEvent],
        calendar: Calendar = .current
    ) -> [Line] {

        let endDay = calendar.startOfDay(for: now)
        let floor = calendar.date(byAdding: .day, value: -(maxLookbackDays - 1), to: endDay) ?? endDay
        var day = max(calendar.startOfDay(for: from), floor)

        var lines: [Line] = []
        while day <= endDay {
            let slots = DayPlan.slots(
                on: day,
                schedules: schedules,
                medications: medications,
                doseEvents: doseEvents,
                calendar: calendar
            )
            for line in slots {
                let plannedAt = line.time.date(on: day, calendar: calendar)
                guard plannedAt <= now else { continue }
                let unrecorded = line.entries.filter { $0.status == nil }
                guard !unrecorded.isEmpty else { continue }
                lines.append(Line(day: day, slot: line.slot, plannedAt: plannedAt, entries: unrecorded))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return lines.sorted { $0.plannedAt < $1.plannedAt }
    }

    /// 줄 하나의 제목: "9월 9일 화요일 · 아침" / "Tue, Sep 9 · Morning".
    public static func title(
        for line: Line,
        language: JanjanLanguage = .standard,
        calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateFormat = language == .english ? "EEE, MMM d" : "M월 d일 EEEE"
        return "\(formatter.string(from: line.day)) · \(line.slot.label(language))"
    }
}
