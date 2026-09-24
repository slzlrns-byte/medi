import Foundation
import SwiftData
import JanjanCore

/// 하루 한 장의 체크인을 저장하는 통로.
///
/// 오늘 화면의 기분 원탭과 워치의 기분 원탭이 같은 규칙을 쓰게 하려고 여기 모았다.
/// 규칙은 하나다 — **하루에 한 장.** 같은 날 다시 고르면 덮어쓴다.
@MainActor
enum CheckInRecorder {

    /// 그 날의 체크인. 없으면 nil.
    ///
    /// 날짜를 `==` 로 비교하지 않고 하루 범위로 찾는다. 저장할 때는 늘 자정으로 맞추지만,
    /// 한 번이라도 어긋난 값이 들어오면 `==` 는 그 줄을 영영 못 찾고 매일 새 줄을 만든다.
    static func record(
        on day: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> CheckInRecord? {

        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }

        var descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// 기분 점수를 남기거나 고친다. 나머지 칸(수면·감정 단어·긴 글)은 건드리지 않는다 —
    /// 워치에서 기분만 톡 눌렀다고 아침에 쓴 일기가 지워지면 안 된다.
    @discardableResult
    static func recordMood(
        score: Int,
        on day: Date,
        at moment: Date = Date(),
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> CheckInRecord {

        let mood = CheckIn.Mood(score)

        if let existing = record(on: day, in: context, calendar: calendar) {
            existing.moodScore = mood.score
            existing.updatedAt = moment
            return existing
        }

        let checkIn = CheckIn(
            date: calendar.startOfDay(for: day),
            mood: mood,
            updatedAt: moment
        )
        let record = CheckInRecord.make(from: checkIn)
        context.insert(record)
        return record
    }
}
