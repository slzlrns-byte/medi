import XCTest
@testable import JanjanCore

/// 복약률과 소진 예측. 설계 05절의 예시를 그대로 재현한다:
/// 8/1 처방 28일분, 하루 1정 → 8/17 까지 복용 14 · 건너뜀 2 · 미기록 1
/// → 잔여 14, 복약률 14/17(82%), 약 17일, 예상 소진 9/3, 다음 진료 8/29 → 알림 없음.
final class ProjectionTests: XCTestCase {

    private let asOf = Fixed.date(2026, 8, 17, 23, 0)

    // MARK: - 복약률

    func testAdherenceRateMatchesWorkedExample() {
        let rate = InventoryCalculator.adherenceRate(
            doseEvents: Fixed.workedExampleDoses(),
            medicationID: Fixed.medA,
            last28DaysEndingAt: asOf,
            calendar: Fixed.calendar
        )
        XCTAssertEqual(rate, Decimal(14) / Decimal(17))

        // 82% 로 표시된다.
        let percent = DecimalQuantity.round((rate ?? 0) * 100, scale: 0)
        XCTAssertEqual(percent, 82)
    }

    func testAdherenceIgnoresAsNeededDoses() {
        var events = Fixed.workedExampleDoses()
        // 필요시 약을 안 먹었다고 복약률이 떨어지면 안 된다.
        for day in 1...10 {
            events.append(
                DoseEvent(medicationID: Fixed.medA,
                          scheduledAt: Fixed.date(2026, 8, day, 15),
                          status: .unrecorded,
                          quantity: 1,
                          kind: .asNeeded)
            )
        }

        let rate = InventoryCalculator.adherenceRate(
            doseEvents: events,
            medicationID: Fixed.medA,
            last28DaysEndingAt: asOf,
            calendar: Fixed.calendar
        )
        XCTAssertEqual(rate, Decimal(14) / Decimal(17))
    }

    func testAdherenceIsNilWhenNothingScheduled() {
        let rate = InventoryCalculator.adherenceRate(
            doseEvents: [],
            medicationID: Fixed.medA,
            last28DaysEndingAt: asOf,
            calendar: Fixed.calendar
        )
        XCTAssertNil(rate, "셀 사건이 없으면 0% 가 아니라 '모름'이다")
    }

    // MARK: - 소진 예측

    func testProjectedDaysAndRunOutDateMatchWorkedExample() {
        let remaining = InventoryCalculator.remaining(
            for: Fixed.medA,
            stockEvents: Fixed.workedExampleStock(),
            doseEvents: Fixed.workedExampleDoses(),
            asOf: asOf
        )
        let rate = InventoryCalculator.adherenceRate(
            doseEvents: Fixed.workedExampleDoses(),
            medicationID: Fixed.medA,
            last28DaysEndingAt: asOf,
            calendar: Fixed.calendar
        )

        let days = InventoryCalculator.projectedDaysRemaining(
            remaining: remaining, dailyScheduledQuantity: 1, adherence: rate
        )
        XCTAssertNotNil(days)
        XCTAssertEqual(DecimalQuantity.round(days ?? 0, scale: 2), 17)

        let runOut = InventoryCalculator.projectedRunOutDate(
            remaining: remaining, dailyScheduledQuantity: 1, adherence: rate,
            from: asOf, calendar: Fixed.calendar
        )
        XCTAssertEqual(runOut, Fixed.date(2026, 9, 3, 0, 0))
    }

    func testLowerAdherencePushesRunOutDateBack() {
        let full = InventoryCalculator.projectedDaysRemaining(
            remaining: 14, dailyScheduledQuantity: 1, adherence: 1
        )
        let partial = InventoryCalculator.projectedDaysRemaining(
            remaining: 14, dailyScheduledQuantity: 1, adherence: Fixed.decimal("0.5")
        )
        XCTAssertEqual(full, 14)
        XCTAssertEqual(partial, 28, "복약률 50% 면 두 배로 오래 간다")
    }

    func testAdherenceFloorKeepsProjectionFinite() {
        let days = InventoryCalculator.projectedDaysRemaining(
            remaining: 10, dailyScheduledQuantity: 1, adherence: 0
        )
        // 0 으로 나누지 않고 하한 5% 를 쓴다 → 10 / 0.05 = 200일.
        XCTAssertEqual(days, 200)
    }

    func testProjectionIsNilWithoutASchedule() {
        XCTAssertNil(
            InventoryCalculator.projectedDaysRemaining(
                remaining: 10, dailyScheduledQuantity: 0, adherence: 1
            ),
            "필요시 약처럼 하루 예정 개수가 없으면 소진일을 말하지 않는다"
        )
    }

    func testProjectionIsZeroWhenNothingLeft() {
        XCTAssertEqual(
            InventoryCalculator.projectedDaysRemaining(
                remaining: 0, dailyScheduledQuantity: 1, adherence: 1
            ),
            0
        )
    }

    // MARK: - 진료일 기준 부족

    func testNoShortfallWhenSupplyCoversNextVisit() {
        let shortfall = InventoryCalculator.shortfallBeforeAppointment(
            remaining: 14,
            dailyScheduledQuantity: 1,
            adherence: Decimal(14) / Decimal(17),
            from: asOf,
            nextVisit: Fixed.date(2026, 8, 29),
            calendar: Fixed.calendar
        )
        XCTAssertNil(shortfall, "12일 뒤 진료인데 17일치가 남아 있으면 알리지 않는다")
    }

    func testShortfallDaysBeforeAppointment() {
        // 6정 남았고 하루 1정, 복약률 100%, 진료까지 10일 → 4일 모자람.
        let shortfall = InventoryCalculator.shortfallBeforeAppointment(
            remaining: 6,
            dailyScheduledQuantity: 1,
            adherence: 1,
            from: asOf,
            nextVisit: Fixed.date(2026, 8, 27),
            calendar: Fixed.calendar
        )
        XCTAssertEqual(shortfall, 4)
    }

    func testShortfallIsNilForPastAppointment() {
        XCTAssertNil(
            InventoryCalculator.shortfallBeforeAppointment(
                remaining: 1,
                dailyScheduledQuantity: 1,
                adherence: 1,
                from: asOf,
                nextVisit: Fixed.date(2026, 8, 10),
                calendar: Fixed.calendar
            )
        )
    }

    // MARK: - 묶어서

    func testSnapshotCombinesRemainingAdherenceAndProjection() {
        let schedule = Schedule(
            medicationID: Fixed.medA,
            slot: .bedtime,
            weekdays: Weekday.everyday,
            dosePerIntake: 1
        )

        let snapshot = InventoryCalculator.snapshot(
            medicationID: Fixed.medA,
            schedules: [schedule],
            stockEvents: Fixed.workedExampleStock(),
            doseEvents: Fixed.workedExampleDoses(),
            nextVisit: Fixed.date(2026, 8, 29),
            asOf: asOf,
            calendar: Fixed.calendar
        )

        XCTAssertEqual(snapshot.remaining, 14)
        XCTAssertEqual(snapshot.dailyScheduledQuantity, 1)
        XCTAssertEqual(snapshot.adherence, Decimal(14) / Decimal(17))
        XCTAssertEqual(DecimalQuantity.round(snapshot.daysRemaining ?? 0, scale: 2), 17)
        XCTAssertEqual(snapshot.runOutDate, Fixed.date(2026, 9, 3, 0, 0))
        XCTAssertNil(snapshot.shortfallDays)
    }

    func testDailyScheduledQuantityConvertsWeeklyPatternToPerDay() {
        let everyDay = [Schedule(medicationID: Fixed.medA, slot: .morning, dosePerIntake: 1)]
        XCTAssertEqual(everyDay.dailyScheduledQuantity(), 1)

        let weekdaysOnly = [
            Schedule(medicationID: Fixed.medA, slot: .morning,
                     weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
                     dosePerIntake: 1)
        ]
        XCTAssertEqual(weekdaysOnly.dailyScheduledQuantity(), Decimal(5) / Decimal(7))
    }
}
