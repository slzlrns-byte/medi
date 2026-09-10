import XCTest
@testable import JanjanCore

/// 잔잔이의 순수 규칙 — 시각으로 정해지는 하루와, 물가에 쌓이는 날 수.
final class JanjaniTests: XCTestCase {

    // MARK: - 하루

    func testPhaseBoundaries() {
        XCTAssertEqual(JanjaniPhase.phase(forHour: 5), .morning)
        XCTAssertEqual(JanjaniPhase.phase(forHour: 10), .morning)
        XCTAssertEqual(JanjaniPhase.phase(forHour: 11), .day)
        XCTAssertEqual(JanjaniPhase.phase(forHour: 18), .day)
        XCTAssertEqual(JanjaniPhase.phase(forHour: 19), .night)
        XCTAssertEqual(JanjaniPhase.phase(forHour: 0), .night)
        XCTAssertEqual(JanjaniPhase.phase(forHour: 4), .night)
    }

    // MARK: - 물가

    private func checkIn(_ day: Int) -> CheckIn {
        CheckIn(
            date: Fixed.calendar.startOfDay(for: Fixed.date(2026, 9, day)),
            mood: .init(0)
        )
    }

    private func dose(_ day: Int, status: DoseEvent.Status) -> DoseEvent {
        DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 9, day, 8, 0),
            status: status,
            source: .phone,
            slotKey: DoseSlot.morning.storageKey
        )
    }

    /// 같은 날 체크인과 복약을 둘 다 적어도 하루는 하루다.
    func testSameDayCountsOnce() {
        let count = JanjaniKeepsakes.recordedDayCount(
            checkIns: [checkIn(3)],
            doseEvents: [dose(3, status: .taken)],
            calendar: Fixed.calendar
        )
        XCTAssertEqual(count, 1)
    }

    func testDifferentDaysAccumulate() {
        let count = JanjaniKeepsakes.recordedDayCount(
            checkIns: [checkIn(1), checkIn(2)],
            doseEvents: [dose(4, status: .skipped)],
            calendar: Fixed.calendar
        )
        XCTAssertEqual(count, 3, "건너뜀도 답이므로 그 날은 셉니다")
    }

    /// 미기록은 답하지 않은 것이라 날로 세지 않는다.
    func testUnrecordedDoseDoesNotCount() {
        let count = JanjaniKeepsakes.recordedDayCount(
            checkIns: [],
            doseEvents: [dose(5, status: .unrecorded)],
            calendar: Fixed.calendar
        )
        XCTAssertEqual(count, 0)
    }

    // MARK: - 직접 넣은 시간대

    func testCustomSlotKnowsItself() {
        XCTAssertTrue(DoseSlot.custom(TimeOfDay(hour: 14, minute: 30)).isCustom)
        XCTAssertFalse(DoseSlot.morning.isCustom)
    }

    /// 저장 키가 시각을 그대로 실어 되돌아와야 어제 등록한 14:30 이 내일도 14:30 이다.
    func testCustomSlotStorageRoundTrip() {
        let slot = DoseSlot.custom(TimeOfDay(hour: 14, minute: 30))
        XCTAssertEqual(DoseSlot(storageKey: slot.storageKey), slot)
    }
}
