import XCTest
@testable import JanjanCore

/// 시리가 "약 먹었어" 만 듣고 시간대를 고르는 규칙.
///
/// 위젯(가장 이른 미답)과 다르다. 화면이 없으므로 **지금 시각과 가장 가까운
/// 미답**을 고른다 - 밤에 말했으면 방금 먹은 것은 취침 약이다.
final class VoicePickTests: XCTestCase {

    private let monday = Fixed.date(2026, 8, 17, 9, 0)

    private let medications = [
        Medication(id: Fixed.medA, name: "에스시탈로프람", strengthText: "10mg"),
        Medication(id: Fixed.medB, name: "쿠에티아핀", strengthText: "25mg")
    ]

    private let schedules = [
        Schedule(medicationID: Fixed.medA, slot: .morning, dosePerIntake: 1),
        Schedule(medicationID: Fixed.medB, slot: .bedtime, dosePerIntake: 1)
    ]

    private func answer(_ slot: DoseSlot, for medicationID: UUID, _ status: DoseEvent.Status) -> DoseEvent {
        let time = slot.defaultTime
        return DoseEvent(
            medicationID: medicationID,
            scheduledAt: Fixed.date(2026, 8, 17, time.hour, time.minute),
            status: status,
            source: .siri,
            slotKey: slot.storageKey
        )
    }

    private func pick(at hour: Int, _ minute: Int, doses: [DoseEvent] = []) -> DayPlan.SlotLine? {
        let lines = DayPlan.slots(
            on: monday,
            schedules: schedules,
            medications: medications,
            doseEvents: doses,
            calendar: Fixed.calendar
        )
        return DayPlan.nearestPending(
            in: lines,
            at: Fixed.date(2026, 8, 17, hour, minute),
            calendar: Fixed.calendar
        )
    }

    /// 밤 10시 35분. 아침도 미답이지만 방금 먹은 것은 취침 약이다.
    /// 위젯이라면 아침을 보여 줬을 시각이다 - 그래서 규칙이 둘로 나뉜다.
    func testAtNightPicksBedtimeEvenWhenMorningIsUnanswered() {
        XCTAssertEqual(pick(at: 22, 35)?.slot, .bedtime)
    }

    func testInTheMorningPicksMorning() {
        XCTAssertEqual(pick(at: 8, 5)?.slot, .morning)
    }

    /// 낮 2시. 취침(22:30)보다 아침(08:00)이 가깝다 - 늦게라도 아침을 적는 셈이다.
    func testInTheAfternoonTheCloserSlotStillWins() {
        XCTAssertEqual(pick(at: 14, 0)?.slot, .morning)
    }

    /// 가까운 쪽이 이미 답해져 있으면 남은 쪽으로 간다.
    func testAnsweredSlotIsSkippedEvenIfCloser() {
        let bedtimeTaken = answer(.bedtime, for: Fixed.medB, .taken)
        XCTAssertEqual(pick(at: 23, 0, doses: [bedtimeTaken])?.slot, .morning)
    }

    func testNothingLeftReturnsNil() {
        let doses = [
            answer(.morning, for: Fixed.medA, .taken),
            answer(.bedtime, for: Fixed.medB, .skipped)
        ]
        XCTAssertNil(pick(at: 12, 0, doses: doses))
    }

    /// 저장되는 문자열이라 값이 바뀌면 지난 기록이 다른 뜻이 된다.
    func testSiriSourceRawValueIsStable() {
        XCTAssertEqual(DoseEvent.Source.siri.rawValue, "siri")
    }
}
