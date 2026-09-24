import XCTest
@testable import JanjanCore

/// 같은 시간대 기록이 둘 이상 생겼을 때.
///
/// 기기가 둘이면 막을 방법이 없다. 워치에서 누르고, 동기화가 오기 전에 폰에서 또 누르면
/// 두 줄이 생기고 CloudKit 은 둘 다 남긴다(유니크 제약을 쓸 수 없다).
/// 그때 화면은 한 줄로 보이는데 재고만 두 번 깎이면, 사용자는 어긋난 숫자를 보면서
/// 이유를 알 길이 없다. 화면과 재고가 같은 규칙을 쓰는지 여기서 지킨다.
final class DuplicateDoseTests: XCTestCase {

    private let day = Fixed.date(2026, 8, 17, 9, 0)

    private func scheduledDose(
        status: DoseEvent.Status = .taken,
        actualAt: Date? = nil,
        quantity: Decimal = 1,
        slot: DoseSlot = .morning
    ) -> DoseEvent {
        let scheduled = Fixed.date(2026, 8, 17, 8, 0)
        return DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: scheduled,
            actualAt: actualAt ?? (status == .taken ? scheduled : nil),
            status: status,
            quantity: quantity,
            kind: .scheduled,
            slotKey: slot.storageKey
        )
    }

    private func remaining(_ doses: [DoseEvent]) -> Decimal {
        InventoryCalculator.remaining(
            for: Fixed.medA,
            stockEvents: [.refill(medicationID: Fixed.medA, quantity: 10, at: Fixed.date(2026, 8, 1))],
            doseEvents: doses,
            asOf: Fixed.date(2026, 8, 18),
            calendar: Fixed.calendar
        )
    }

    func testTwoRecordsOfTheSameSlotSubtractOnce() {
        // 워치와 폰이 각자 만든 두 줄. 사람은 한 알을 먹었다.
        XCTAssertEqual(remaining([scheduledDose(), scheduledDose()]), 9)
    }

    func testOneRecordStillSubtractsOnce() {
        XCTAssertEqual(remaining([scheduledDose()]), 9)
    }

    func testLatestRecordWinsWhenTheyDisagree() {
        // 알림에서 복용함을 눌렀다가 앱에서 건너뜀으로 고쳤다. 약은 줄지 않았다.
        let taken = scheduledDose(status: .taken, actualAt: Fixed.date(2026, 8, 17, 8, 0))
        let skipped = DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 8, 17, 8, 0),
            actualAt: Fixed.date(2026, 8, 17, 10, 0),
            status: .skipped,
            quantity: 1,
            kind: .scheduled,
            slotKey: DoseSlot.morning.storageKey
        )
        XCTAssertEqual(remaining([taken, skipped]), 10)
    }

    func testDifferentSlotsOnTheSameDayBothSubtract() {
        let morning = scheduledDose(slot: .morning)
        let bedtime = DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 8, 17, 22, 30),
            actualAt: Fixed.date(2026, 8, 17, 22, 30),
            status: .taken,
            quantity: 1,
            kind: .scheduled,
            slotKey: DoseSlot.bedtime.storageKey
        )
        XCTAssertEqual(remaining([morning, bedtime]), 8)
    }

    func testDifferentDaysBothSubtract() {
        let today = scheduledDose()
        let yesterday = DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 8, 16, 8, 0),
            actualAt: Fixed.date(2026, 8, 16, 8, 0),
            status: .taken,
            quantity: 1,
            kind: .scheduled,
            slotKey: DoseSlot.morning.storageKey
        )
        XCTAssertEqual(remaining([today, yesterday]), 8)
    }

    func testAsNeededDosesAreNeverCollapsed() {
        // 필요시 약을 하루에 두 번 먹었으면 두 번 먹은 것이 사실이다.
        let first = DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 8, 17, 11, 0),
            actualAt: Fixed.date(2026, 8, 17, 11, 0),
            status: .taken,
            quantity: 1,
            kind: .asNeeded
        )
        let second = DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 8, 17, 17, 0),
            actualAt: Fixed.date(2026, 8, 17, 17, 0),
            status: .taken,
            quantity: 1,
            kind: .asNeeded
        )
        XCTAssertEqual(remaining([first, second]), 8)
    }

    func testScreenAndStockAgreeOnTheSameEvent() {
        // DayPlan 이 고른 줄과 재고가 센 줄이 어긋나면, 화면의 '완료' 와
        // 줄어든 개수가 서로 다른 사실을 말하게 된다.
        let taken = scheduledDose(status: .taken, actualAt: Fixed.date(2026, 8, 17, 8, 0))
        let skipped = DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 8, 17, 8, 0),
            actualAt: Fixed.date(2026, 8, 17, 10, 0),
            status: .skipped,
            quantity: 1,
            kind: .scheduled,
            slotKey: DoseSlot.morning.storageKey
        )

        let plan = DayPlan.slots(
            on: day,
            schedules: [Schedule(medicationID: Fixed.medA, slot: .morning, dosePerIntake: 1)],
            medications: [Medication(id: Fixed.medA, name: "에스시탈로프람")],
            doseEvents: [taken, skipped],
            calendar: Fixed.calendar
        )

        let kept = InventoryCalculator.collapsedDoses(
            for: Fixed.medA,
            in: [taken, skipped],
            calendar: Fixed.calendar
        )

        XCTAssertEqual(plan.first?.entries.first?.status, .skipped)
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.status, .skipped)
    }
}
