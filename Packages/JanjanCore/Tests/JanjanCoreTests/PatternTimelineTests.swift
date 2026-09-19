import XCTest
@testable import JanjanCore

/// "패턴 보기" 계산. 세 줄(기분·복약·수면)이 같은 날짜 열에 놓이는지를 잠근다.
/// 해석(상관·추세)은 만들지 않는다는 원칙은 API 모양 자체로 지켜진다 —
/// 여기에는 날짜별 원자료만 있다.
final class PatternTimelineTests: XCTestCase {

    private let medications = [
        Medication(id: Fixed.medA, name: "에스시탈로프람", strengthText: "10mg")
    ]
    private let schedules = [
        Schedule(medicationID: Fixed.medA, slot: .morning, dosePerIntake: 1)
    ]

    func testDaysRunOldestToNewestAndCount() {
        let timeline = PatternTimeline.make(
            dayCount: 7,
            endingAt: Fixed.date(2026, 9, 10, 15, 0),
            checkIns: [],
            schedules: [],
            medications: [],
            doseEvents: [],
            calendar: Fixed.calendar
        )
        XCTAssertEqual(timeline.days.count, 7)
        XCTAssertEqual(timeline.days.first?.date, Fixed.calendar.startOfDay(for: Fixed.date(2026, 9, 4)))
        XCTAssertEqual(timeline.days.last?.date, Fixed.calendar.startOfDay(for: Fixed.date(2026, 9, 10)))
    }

    func testMoodAndSleepLandOnTheirOwnDay() {
        let checkIn = CheckIn(
            date: Fixed.date(2026, 9, 9, 21, 0),
            mood: .init(2),
            sleepMinutes: 7 * 60,
            updatedAt: Fixed.date(2026, 9, 9, 21, 0)
        )
        let timeline = PatternTimeline.make(
            dayCount: 3,
            endingAt: Fixed.date(2026, 9, 10),
            checkIns: [checkIn],
            schedules: [],
            medications: [],
            doseEvents: [],
            calendar: Fixed.calendar
        )
        XCTAssertEqual(timeline.days[1].moodScore, 2)
        XCTAssertEqual(timeline.days[1].sleepMinutes, 7 * 60)
        XCTAssertNil(timeline.days[0].moodScore)
        XCTAssertNil(timeline.days[2].moodScore)
    }

    /// 답하지 않은 시간대는 기록에 줄이 없다. 계획에서 세어야
    /// "안 답한 날" 과 "계획이 없던 날" 이 구별된다.
    func testDoseCountsComeFromThePlanNotOnlyFromEvents() {
        let taken = DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 9, 9, 8, 0),
            actualAt: Fixed.date(2026, 9, 9, 8, 5),
            status: .taken,
            quantity: 1,
            kind: .scheduled,
            slotKey: DoseSlot.morning.storageKey
        )
        let timeline = PatternTimeline.make(
            dayCount: 2,
            endingAt: Fixed.date(2026, 9, 10),
            checkIns: [],
            schedules: schedules,
            medications: medications,
            doseEvents: [taken],
            calendar: Fixed.calendar
        )
        // 9월 9일: 예정 1 · 복용 1 → 전부.
        XCTAssertEqual(timeline.days[0].scheduledCount, 1)
        XCTAssertEqual(timeline.days[0].takenCount, 1)
        XCTAssertEqual(timeline.days[0].takenFraction, 1.0)
        // 9월 10일: 예정 1 · 답 없음 → 0. 계획이 없던 날(nil)과 다르다.
        XCTAssertEqual(timeline.days[1].scheduledCount, 1)
        XCTAssertEqual(timeline.days[1].takenCount, 0)
        XCTAssertEqual(timeline.days[1].takenFraction, 0.0)
    }

    func testNoScheduleMeansNoFractionNotZero() {
        let timeline = PatternTimeline.make(
            dayCount: 1,
            endingAt: Fixed.date(2026, 9, 10),
            checkIns: [],
            schedules: [],
            medications: medications,
            doseEvents: [],
            calendar: Fixed.calendar
        )
        XCTAssertEqual(timeline.days[0].scheduledCount, 0)
        XCTAssertNil(timeline.days[0].takenFraction, "계획이 없던 날은 0% 가 아니라 빈 칸입니다")
    }
}
