import XCTest
@testable import JanjanCore

/// "이번 달의 물결" 계산. 색을 칠하는 것은 화면 몫이고, 여기서는 어느 칸에
/// 어느 점수가 놓이는지를 잠근다.
final class MonthWaveTests: XCTestCase {

    private func checkIn(_ month: Int, _ day: Int, score: Int, updatedAt: Date? = nil) -> CheckIn {
        CheckIn(
            date: Fixed.calendar.startOfDay(for: Fixed.date(2026, month, day)),
            mood: .init(score),
            updatedAt: updatedAt ?? Fixed.date(2026, month, day, 12, 0)
        )
    }

    func testSeptember2026StartsOnTuesdayWithThirtyDays() {
        let wave = MonthWave.make(
            containing: Fixed.date(2026, 9, 15),
            checkIns: [],
            calendar: Fixed.calendar
        )
        XCTAssertEqual(wave.year, 2026)
        XCTAssertEqual(wave.month, 9)
        XCTAssertEqual(wave.leadingBlanks, 2, "2026년 9월 1일은 화요일 - 일·월 두 칸이 빕니다")
        XCTAssertEqual(wave.days.count, 30)
    }

    func testSundayStartMonthHasNoLeadingBlanks() {
        let wave = MonthWave.make(
            containing: Fixed.date(2026, 11, 3),
            checkIns: [],
            calendar: Fixed.calendar
        )
        XCTAssertEqual(wave.leadingBlanks, 0, "2026년 11월 1일은 일요일입니다")
    }

    func testMoodLandsOnItsOwnDay() {
        let wave = MonthWave.make(
            containing: Fixed.date(2026, 9, 15),
            checkIns: [checkIn(9, 5, score: 2)],
            calendar: Fixed.calendar
        )
        XCTAssertEqual(wave.days[4].day, 5)
        XCTAssertEqual(wave.days[4].moodScore, 2)
        XCTAssertNil(wave.days[5].moodScore, "기록 없는 날은 빈 칸입니다")
    }

    /// 8월 31일의 기록이 9월 그림에 스며들면 달이 거짓말을 하게 된다.
    func testOtherMonthsAreExcluded() {
        let wave = MonthWave.make(
            containing: Fixed.date(2026, 9, 15),
            checkIns: [checkIn(8, 31, score: -3), checkIn(10, 1, score: 3)],
            calendar: Fixed.calendar
        )
        XCTAssertTrue(wave.days.allSatisfy { $0.moodScore == nil })
    }

    /// 같은 날을 고쳐 적으면 마지막 손이 이긴다. 기록을 고치는 것은 사용자의
    /// 권리고, 그림은 항상 지금의 기록을 말해야 한다.
    func testLatestEditWinsOnTheSameDay() {
        let wave = MonthWave.make(
            containing: Fixed.date(2026, 9, 15),
            checkIns: [
                checkIn(9, 10, score: -2, updatedAt: Fixed.date(2026, 9, 10, 9, 0)),
                checkIn(9, 10, score: 1, updatedAt: Fixed.date(2026, 9, 10, 21, 0))
            ],
            calendar: Fixed.calendar
        )
        XCTAssertEqual(wave.days[9].moodScore, 1)
    }
}
