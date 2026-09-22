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

/// 앱이 채운 미기록과 사용자가 고른 "기억나지 않아요" 는 같은 상태값을
/// 쓰지만 뜻이 다르다. 하나는 답이 아니고 하나는 답이다.
final class AutoFilledUnrecordedTests: XCTestCase {

    private let calendar = Fixed.calendar
    private let day = Fixed.date(2026, 9, 12)

    private var medication: Medication {
        Medication(id: Fixed.medA, name: "에스시탈로프람")
    }

    private var morning: Schedule {
        Schedule(medicationID: Fixed.medA, slot: .morning, weekdays: Weekday.everyday)
    }

    private func event(source: DoseEvent.Source) -> DoseEvent {
        DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 9, 12, 8, 0),
            status: .unrecorded,
            source: source,
            quantity: 1,
            kind: .scheduled,
            slotKey: DoseSlot.morning.storageKey
        )
    }

    /// **하루만 본다.** 다음 날까지 창을 열면 그 날의 아침이 답이 없어
    /// 늘 걸리므로, 출처에 따른 차이를 재는 저울이 못 된다(CI 124 에서
    /// 이 테스트가 그렇게 헛돌았다).
    private func asksAgain(source: DoseEvent.Source) -> Bool {
        !UnrecordedSlots.find(
            from: day,
            until: Fixed.date(2026, 9, 12, 23, 0),
            schedules: [morning],
            medications: [medication],
            doseEvents: [event(source: source)],
            calendar: calendar
        ).isEmpty
    }

    func testAppFilledUnrecordedIsStillAsked() {
        XCTAssertTrue(asksAgain(source: .automatic), "앱이 채운 것은 답이 아니라 계속 물어본다")
    }

    func testUserAnsweredDontRememberIsNotAskedAgain() {
        XCTAssertFalse(asksAgain(source: .phone), "직접 고른 답을 다시 묻지 않는다")
        XCTAssertFalse(asksAgain(source: .notificationAction))
        XCTAssertFalse(asksAgain(source: .watch))
    }

    /// **분모에 들어가지 않는다**(2026-09-22 에 뒤집음). 예전에는 "앱을 안 연
    /// 날이 복약률에서 사라지지 않게" 넣었는데, 이 비율은 이제 진료실 복약률이
    /// 아니라 **소진 예측**에만 쓰인다. 요일을 넓히면 지난 4주의 새 요일이
    /// 전부 이 줄로 채워져 꼬박 먹은 사람의 비율이 반으로 내려가고 "부족한 약
    /// 없음" 이 떴다. 물어볼 자리이지 답이 아니다. 직접 고른 "기억나지
    /// 않아요" 는 답이라 그대로 센다(`AdherenceRateBackfillTests`).
    func testFilledUnrecordedStaysOutOfTheDenominator() {
        let taken = DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 9, 11, 8, 0),
            actualAt: Fixed.date(2026, 9, 11, 8, 5),
            status: .taken,
            quantity: 1,
            kind: .scheduled,
            slotKey: DoseSlot.morning.storageKey
        )
        let rate = InventoryCalculator.adherenceRate(
            doseEvents: [taken, event(source: .automatic)],
            from: Fixed.date(2026, 9, 11, 0, 0),
            to: Fixed.date(2026, 9, 13, 0, 0),
            calendar: calendar
        )
        XCTAssertEqual(rate, 1, "앱이 채운 줄은 세지 않으니 복용한 하루만 남는다")

        let answered = InventoryCalculator.adherenceRate(
            doseEvents: [taken, event(source: .phone)],
            from: Fixed.date(2026, 9, 11, 0, 0),
            to: Fixed.date(2026, 9, 13, 0, 0),
            calendar: calendar
        )
        XCTAssertEqual(answered, Decimal(1) / Decimal(2), "직접 고른 '기억나지 않아요' 는 절반으로 센다")
    }
}
