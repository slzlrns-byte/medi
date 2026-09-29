import XCTest
@testable import JanjanCore

/// 안전 카드를 언제 내미는지.
///
/// 이 규칙은 양쪽으로 다 위험하다. 놓치면 필요한 순간에 연락처가 안 보이고,
/// 헤프면 카드가 잔소리가 되어 사용자가 기분을 솔직하게 적지 않게 된다.
final class SafetyTriggerTests: XCTestCase {

    private let today = Fixed.date(2026, 8, 17, 21, 0)

    private func checkIn(_ day: Int, _ score: Int, updatedAt: Date? = nil) -> CheckIn {
        let date = Fixed.calendar.startOfDay(for: Fixed.date(2026, 8, day, 12, 0))
        return CheckIn(date: date, mood: .init(score), updatedAt: updatedAt ?? date)
    }

    private func run(_ checkIns: [CheckIn]) -> Int {
        SafetyTrigger.consecutiveLowMoodDays(
            checkIns: checkIns,
            endingAt: today,
            calendar: Fixed.calendar
        )
    }

    private func moodReason(_ checkIns: [CheckIn]) -> SafetyTrigger.Reason? {
        SafetyTrigger.reason(forCheckIns: checkIns, endingAt: today, calendar: Fixed.calendar)
    }

    // MARK: - 증상

    func testSafetySymptomTriggersTheCard() {
        // 카탈로그에서 safety: true 로 표시된 항목.
        XCTAssertEqual(
            SafetyTrigger.reason(forSavedSymptomID: "self_harm_thoughts"),
            .safetySymptom(symptomID: "self_harm_thoughts")
        )
    }

    func testOrdinarySymptomDoesNotTriggerTheCard() {
        XCTAssertNil(SafetyTrigger.reason(forSavedSymptomID: "anxiety_restless"))
    }

    func testUnknownSymptomDoesNotTriggerTheCard() {
        XCTAssertNil(SafetyTrigger.reason(forSavedSymptomID: "삭제된_항목"))
    }

    func testCatalogStillMarksExactlyTheSafetyItem() {
        // 카탈로그를 손보다 safety 표시를 지우면 이 기능이 조용히 죽는다.
        let flagged = Catalogs.symptoms.safetyItems.map(\.id)
        XCTAssertEqual(flagged, ["self_harm_thoughts"])
    }

    // MARK: - 이어지는 기분

    func testThreeConsecutiveLowestDaysTriggerTheCard() {
        let days = [checkIn(15, -3), checkIn(16, -3), checkIn(17, -3)]
        XCTAssertEqual(run(days), 3)
        XCTAssertEqual(moodReason(days), .lowMoodRun(days: 3))
    }

    func testTwoDaysIsNotEnough() {
        let days = [checkIn(16, -3), checkIn(17, -3)]
        XCTAssertEqual(run(days), 2)
        XCTAssertNil(moodReason(days))
    }

    func testRunMustReachToday() {
        // 사흘 이어졌지만 그게 지난주라면 오늘 카드를 올리지 않는다.
        let days = [checkIn(10, -3), checkIn(11, -3), checkIn(12, -3)]
        XCTAssertEqual(run(days), 0)
        XCTAssertNil(moodReason(days))
    }

    func testMissingDayBreaksTheRun() {
        // 며칠 앱을 열지 않았다는 이유만으로 카드가 올라오면 안 된다.
        let days = [checkIn(14, -3), checkIn(15, -3), checkIn(17, -3)]
        XCTAssertEqual(run(days), 1)
        XCTAssertNil(moodReason(days))
    }

    func testABetterDayBreaksTheRun() {
        let days = [checkIn(15, -3), checkIn(16, -2), checkIn(17, -3)]
        XCTAssertEqual(run(days), 1)
        XCTAssertNil(moodReason(days))
    }

    func testRunKeepsCountingPastThree() {
        let days = (13...17).map { checkIn($0, -3) }
        XCTAssertEqual(run(days), 5)
        XCTAssertEqual(moodReason(days), .lowMoodRun(days: 5))
    }

    func testNoCheckInsAtAll() {
        XCTAssertEqual(run([]), 0)
        XCTAssertNil(moodReason([]))
    }

    func testLatestEditOfADayWins() {
        // 아침에 −3 으로 적었다가 밤에 −1 로 고쳤으면, 고친 쪽이 사실이다.
        let morning = checkIn(17, -3, updatedAt: Fixed.date(2026, 8, 17, 9, 0))
        let evening = checkIn(17, -1, updatedAt: Fixed.date(2026, 8, 17, 22, 0))
        let days = [checkIn(15, -3), checkIn(16, -3), morning, evening]
        XCTAssertEqual(run(days), 0)
        XCTAssertNil(moodReason(days))
    }

    // MARK: - 연락처

    func testKoreanContactsAreDialable() {
        let contacts = Janjan.crisisContacts(regionCode: "kr")
        XCTAssertEqual(contacts.count, 2)
        XCTAssertEqual(contacts.map(\.dialDigits), ["109", "15770199"])
    }

    func testUnverifiedRegionGetsNoInventedNumbers() {
        // 틀린 번호를 내미는 것은 아무 번호도 없는 것보다 나쁘다.
        XCTAssertTrue(Janjan.crisisContacts(regionCode: "US").isEmpty)
        XCTAssertTrue(Janjan.crisisContacts(regionCode: nil).isEmpty)
    }

    func testBothSafetyMessagesAreCalmAndUnjudging() {
        for message in [Janjan.safetyCardMessageKo, Janjan.safetyCardWithoutContactsKo] {
            XCTAssertFalse(message.contains("!"))
            for word in ["위험", "경고", "즉시", "반드시", "심각"] {
                XCTAssertFalse(message.contains(word), "겁주는 말이 들어갔습니다: \(message)")
            }
        }
    }
}
