import XCTest
@testable import JanjanCore

/// 계획은 저장하지 않고 매번 지금의 스케줄로 다시 만든다. 그래서 "언제부터
/// 있었는가" 를 모르면 오늘 등록한 약이 지난 한 달 내내 있었던 것이 된다.
///
/// 이 테스트가 지키는 것은 진료실에 나가는 숫자다 - 존재한 적 없는 처방의
/// 미기록이 복약률 분모에 섞이면 의사가 잘못된 숫자를 본다(QA 2026-09-19).
final class PlanStartTests: XCTestCase {

    private let calendar = Fixed.calendar
    private let registeredOn = Fixed.date(2026, 9, 19, 10, 0)

    private var freshMedication: Medication {
        Medication(id: Fixed.medA, name: "졸피뎀", createdAt: registeredOn)
    }

    private var morningEveryDay: Schedule {
        Schedule(medicationID: Fixed.medA, slot: .morning, weekdays: Weekday.everyday)
    }

    func testPlanIsEmptyBeforeTheMedicationWasRegistered() {
        let lines = DayPlan.slots(
            on: Fixed.date(2026, 9, 12),
            schedules: [morningEveryDay],
            medications: [freshMedication],
            doseEvents: [],
            calendar: calendar
        )
        XCTAssertTrue(lines.isEmpty, "등록하기 전 날에는 계획이 없어야 한다")
    }

    func testPlanExistsOnTheDayItWasRegistered() {
        let lines = DayPlan.slots(
            on: registeredOn,
            schedules: [morningEveryDay],
            medications: [freshMedication],
            doseEvents: [],
            calendar: calendar
        )
        XCTAssertEqual(lines.count, 1, "등록한 날부터는 계획이 있다")
    }

    /// 등록 직후 오늘 화면을 열었을 때 지난 이레가 통째로 "빠트린 날" 로
    /// 쏟아지던 것이 이 케이스다.
    func testNewMedicationDoesNotCreateMissedDaysInThePast() {
        let lines = UnrecordedSlots.find(
            from: Fixed.date(2026, 9, 12),
            until: registeredOn,
            schedules: [morningEveryDay],
            medications: [freshMedication],
            doseEvents: [],
            calendar: calendar
        )
        XCTAssertTrue(
            lines.allSatisfy { $0.day >= calendar.startOfDay(for: registeredOn) },
            "등록 전 날짜가 빠트림으로 올라오면 안 된다"
        )
    }

    /// 언제부터였는지 모르는 값(저장소를 거치지 않은 것)은 막지 않는다.
    func testUnknownStartDoesNotBlockThePlan() {
        let unknown = Medication(id: Fixed.medA, name: "졸피뎀")
        let lines = DayPlan.slots(
            on: Fixed.date(2026, 9, 12),
            schedules: [morningEveryDay],
            medications: [unknown],
            doseEvents: [],
            calendar: calendar
        )
        XCTAssertEqual(lines.count, 1, "모르면 막지 않는다")
    }

    /// 아침만 먹던 약에 저녁을 더했을 때, 지난 한 달의 저녁이 되살아나면 안 된다.
    func testSlotAddedLaterDoesNotReachBackwards() {
        let addedToday = Schedule(
            medicationID: Fixed.medA,
            slot: .evening,
            weekdays: Weekday.everyday,
            startDate: registeredOn
        )
        let longStanding = Medication(
            id: Fixed.medA,
            name: "졸피뎀",
            createdAt: Fixed.date(2026, 7, 1, 10, 0)
        )

        let before = DayPlan.slots(
            on: Fixed.date(2026, 9, 12),
            schedules: [addedToday],
            medications: [longStanding],
            doseEvents: [],
            calendar: calendar
        )
        XCTAssertTrue(before.isEmpty, "더하기 전 날에는 그 시간대가 없다")

        let after = DayPlan.slots(
            on: registeredOn,
            schedules: [addedToday],
            medications: [longStanding],
            doseEvents: [],
            calendar: calendar
        )
        XCTAssertEqual(after.count, 1)
    }
}
