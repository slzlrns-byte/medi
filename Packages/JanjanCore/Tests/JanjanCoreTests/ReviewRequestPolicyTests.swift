import XCTest
@testable import JanjanCore

/// 별점 창의 문턱. 출시 직후에는 낮고, 날짜가 지나면 저절로 원래대로
/// 돌아간다 - 빌드를 다시 내지 않아도 되게 날짜로 자른 것이라, 그 경계가
/// 정확한지가 요점이다.
final class ReviewRequestPolicyTests: XCTestCase {

    func testLaunchWindowAsksAfterThreeDistinctDays() {
        let during = Fixed.date(2026, 10, 15)
        XCTAssertEqual(ReviewRequestPolicy.requiredRecordedDays(asOf: during), 3)
        XCTAssertFalse(ReviewRequestPolicy.shouldAsk(recordedDays: 2, asOf: during))
        XCTAssertTrue(ReviewRequestPolicy.shouldAsk(recordedDays: 3, asOf: during))
    }

    func testAfterLaunchWindowAsksAfterSevenDistinctDays() {
        let later = Fixed.date(2027, 3, 1)
        XCTAssertEqual(ReviewRequestPolicy.requiredRecordedDays(asOf: later), 7)
        XCTAssertFalse(ReviewRequestPolicy.shouldAsk(recordedDays: 6, asOf: later))
        XCTAssertTrue(ReviewRequestPolicy.shouldAsk(recordedDays: 7, asOf: later))
    }

    /// 경계는 한국 시각 12월 31일 자정이다. 그 직전은 낮은 문턱, 직후는 평소 문턱.
    func testBoundaryIsKoreaMidnightOnNewYearsEve() {
        let end = ReviewRequestPolicy.launchWindowEnd
        XCTAssertEqual(ReviewRequestPolicy.requiredRecordedDays(asOf: end), 3)
        XCTAssertEqual(ReviewRequestPolicy.requiredRecordedDays(asOf: end.addingTimeInterval(1)), 7)

        var seoul = Calendar(identifier: .gregorian)
        seoul.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let parts = seoul.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 12)
        XCTAssertEqual(parts.day, 31)
        XCTAssertEqual(parts.hour, 23)
        XCTAssertEqual(parts.minute, 59)
        XCTAssertEqual(parts.second, 59)
    }

    /// 어느 단계에서든 한 번도 기록 안 한 사람에게는 청하지 않는다.
    func testNeverAsksWithoutRecords() {
        XCTAssertFalse(ReviewRequestPolicy.shouldAsk(recordedDays: 0, asOf: Fixed.date(2026, 10, 1)))
        XCTAssertFalse(ReviewRequestPolicy.shouldAsk(recordedDays: 0, asOf: Fixed.date(2027, 6, 1)))
    }
}
