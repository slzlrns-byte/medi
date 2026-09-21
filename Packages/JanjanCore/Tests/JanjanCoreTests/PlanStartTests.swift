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

    /// **분모에 들어가지 않는다**(사용자 결정 2026-09-21).
    ///
    /// 예전에는 채운 미기록을 분모에 넣었다 - 앱을 안 연 날이 복약률에서
    /// 사라지지 않게 하려는 뜻이었다. 그런데 계획은 저장하지 않고 지금의
    /// 요일로 매번 다시 그리는 구조라, 요일을 넓히기만 해도 앱이 지난 4주의
    /// 안 먹는 날을 "빠트림" 으로 채워 100% 가 42% 로 내려갔다. 한 번도
    /// 안 빠트린 사람의 숫자였고 그것이 진료실로 나갔다.
    ///
    /// 미기록은 "안 먹었다" 가 아니라 "답이 없다" 다. 앱이 모르는 것을
    /// 안 먹은 것으로 바꿔 말하지 않는다. 대신 비율 옆에 늘 답한 날 수를
    /// 붙여, 5일로 잰 100% 와 28일로 잰 100% 를 구별할 수 있게 한다.
    ///
    /// 채우기 자체는 남는다 - "기록 없이 지나간 시간대" 가 그 줄들로
    /// 사용자에게 다시 물어본다.
    func testFilledUnrecordedIsLeftOutOfTheRate() {
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
        XCTAssertEqual(rate, 1, "답한 것은 복용함 하나뿐이라 100% 다")

        // 그래도 그 숫자가 며칠로 잰 것인지는 함께 나가야 한다.
        XCTAssertEqual(
            InventoryCalculator.answeredDayCount(
                doseEvents: [taken, event(source: .automatic)],
                from: Fixed.date(2026, 9, 11, 0, 0),
                to: Fixed.date(2026, 9, 13, 0, 0),
                calendar: calendar
            ),
            1,
            "답이 남은 날은 하루뿐이다"
        )
    }

    /// 건너뜀은 답이므로 분모에 들어간다. "안 먹었다" 와 "모른다" 는 다르다.
    func testSkippedStaysInTheDenominator() {
        let taken = DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 9, 11, 8, 0),
            actualAt: Fixed.date(2026, 9, 11, 8, 5),
            status: .taken,
            quantity: 1,
            kind: .scheduled,
            slotKey: DoseSlot.morning.storageKey
        )
        // 채운 미기록(9/12 아침)과 같은 칸에 두면 둘이 하나로 묶여
        // 무엇이 남을지 정해지지 않는다. 다른 시간대로 둔다.
        let skipped = DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 9, 11, 19, 0),
            status: .skipped,
            quantity: 1,
            kind: .scheduled,
            slotKey: DoseSlot.evening.storageKey
        )
        let rate = InventoryCalculator.adherenceRate(
            doseEvents: [taken, skipped, event(source: .automatic)],
            from: Fixed.date(2026, 9, 11, 0, 0),
            to: Fixed.date(2026, 9, 13, 0, 0),
            calendar: calendar
        )
        XCTAssertEqual(rate, Decimal(1) / Decimal(2), "복용 1 · 건너뜀 1 → 절반")
    }
}
