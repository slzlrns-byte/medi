import XCTest
@testable import JanjanCore

/// 용량 변경 전후 비교의 규칙: 사실만 세고 해석은 하지 않는다.
/// 변경 당일은 "후" 에 속하고, 아직 다 지나지 않은 "후" 는 오늘까지만 센다.
final class DoseChangeComparisonTests: XCTestCase {

    // 8/15 에 5mg → 10mg. 오늘은 8/24 (후 구간이 9일만 참).
    private let changedAt = Fixed.date(2026, 8, 15, 10, 0)
    private let now = Fixed.date(2026, 8, 24, 12, 0)

    private var change: DoseChange {
        DoseChange(medicationID: Fixed.medA, changedAt: changedAt, fromText: "5mg", toText: "10mg")
    }

    private func checkIn(_ day: Int, mood: Int, sleep: Int? = nil, dreamed: Bool? = nil, nightmare: Bool? = nil) -> CheckIn {
        CheckIn(
            date: Fixed.calendar.startOfDay(for: Fixed.date(2026, 8, day)),
            mood: .init(mood),
            sleepMinutes: sleep,
            dreamed: dreamed,
            nightmare: nightmare
        )
    }

    func testWindowsSplitAtTheChangeDay() {
        let comparison = DoseChangeComparison.make(
            change: change,
            checkIns: [
                checkIn(10, mood: -2, sleep: 6 * 60),   // 전
                checkIn(14, mood: -1, sleep: 7 * 60),   // 전 (변경 전날)
                checkIn(15, mood: 0),                    // 후 (변경 당일)
                checkIn(20, mood: 1, sleep: 8 * 60, dreamed: true, nightmare: true)
            ],
            symptomEntries: [
                SymptomEntry(symptomID: "drowsiness", severity: 6, startedAt: Fixed.date(2026, 8, 12, 9, 0)),
                SymptomEntry(symptomID: "drowsiness", severity: 4, startedAt: Fixed.date(2026, 8, 12, 21, 0)),
                SymptomEntry(symptomID: "dry_mouth", severity: 3, startedAt: Fixed.date(2026, 8, 21, 9, 0))
            ],
            now: now,
            calendar: Fixed.calendar
        )

        XCTAssertEqual(comparison.before.days, 14)
        XCTAssertEqual(comparison.after.days, 10)  // 8/15 ~ 8/24 (오늘 포함)

        XCTAssertEqual(comparison.before.moodRecordedDays, 2)
        XCTAssertEqual(comparison.before.moodAverage, -1.5)
        XCTAssertEqual(comparison.before.sleepAverageMinutes, 390)
        // 같은 날 두 건이어도 증상 "일수" 는 하루다.
        XCTAssertEqual(comparison.before.symptomDays, 1)
        XCTAssertEqual(comparison.before.dreamDays, 0)

        XCTAssertEqual(comparison.after.moodRecordedDays, 2)
        XCTAssertEqual(comparison.after.moodAverage, 0.5)
        XCTAssertEqual(comparison.after.sleepAverageMinutes, 8 * 60)
        XCTAssertEqual(comparison.after.symptomDays, 1)
        XCTAssertEqual(comparison.after.dreamDays, 1)
        XCTAssertEqual(comparison.after.nightmareDays, 1)
        XCTAssertTrue(comparison.hasAnything)
    }

    func testEmptyWindowsStayEmptyInsteadOfPretending() {
        let comparison = DoseChangeComparison.make(
            change: change, checkIns: [], symptomEntries: [],
            now: now, calendar: Fixed.calendar
        )
        XCTAssertNil(comparison.before.moodAverage)
        XCTAssertNil(comparison.before.sleepAverageMinutes)
        XCTAssertFalse(comparison.hasAnything)
    }

    func testDisplayFragmentsSpeakInSignsAndUnits() {
        XCTAssertEqual(DoseChangeComparison.moodText(-0.6), "-0.6")
        XCTAssertEqual(DoseChangeComparison.moodText(1.2), "+1.2")
        XCTAssertEqual(DoseChangeComparison.moodText(0), "0.0")
        XCTAssertNil(DoseChangeComparison.moodText(nil))
        XCTAssertEqual(DoseChangeComparison.sleepText(421, language: .korean), "7시간 1분")
        XCTAssertEqual(DoseChangeComparison.sleepText(420, language: .english), "7h")
        XCTAssertEqual(DoseChangeComparison.sleepText(421, language: .english), "7h 1m")
    }

    func testSameDayDuplicateCheckInsCountOnce() {
        // 기기 둘이 같은 날 체크인을 두 줄로 만들었어도 하루로 센다.
        let day = Fixed.calendar.startOfDay(for: Fixed.date(2026, 8, 20))
        let older = CheckIn(date: day, mood: .init(-2), updatedAt: Fixed.date(2026, 8, 20, 9, 0))
        let newer = CheckIn(date: day, mood: .init(2), updatedAt: Fixed.date(2026, 8, 20, 21, 0))
        let comparison = DoseChangeComparison.make(
            change: change, checkIns: [older, newer], symptomEntries: [],
            now: now, calendar: Fixed.calendar
        )
        XCTAssertEqual(comparison.after.moodRecordedDays, 1)
        XCTAssertEqual(comparison.after.moodAverage, 2.0)  // 나중에 손댄 쪽
    }
}
