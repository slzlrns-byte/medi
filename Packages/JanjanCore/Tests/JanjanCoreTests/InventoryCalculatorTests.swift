import XCTest
@testable import JanjanCore

/// 설계 05절 "재고는 사건의 합" 규칙을 한 줄씩 확인한다.
/// 이 파일이 초록이 아니면 잔여 개수를 화면에 띄우면 안 된다.
final class InventoryCalculatorTests: XCTestCase {

    // MARK: - 차감 규칙

    func testTakenSubtractsFromStock() {
        let stock: [StockEvent] = [
            .refill(medicationID: Fixed.medA, quantity: 10, at: Fixed.date(2026, 8, 1))
        ]
        let doses = [
            DoseEvent(medicationID: Fixed.medA, scheduledAt: Fixed.date(2026, 8, 2, 21), status: .taken, quantity: 1),
            DoseEvent(medicationID: Fixed.medA, scheduledAt: Fixed.date(2026, 8, 3, 21), status: .taken, quantity: 1)
        ]

        let remaining = InventoryCalculator.remaining(
            for: Fixed.medA, stockEvents: stock, doseEvents: doses, asOf: Fixed.date(2026, 8, 4)
        )
        XCTAssertEqual(remaining, 8)
    }

    func testSkippedDoesNotSubtract() {
        let stock: [StockEvent] = [
            .refill(medicationID: Fixed.medA, quantity: 10, at: Fixed.date(2026, 8, 1))
        ]
        let doses = [
            DoseEvent(medicationID: Fixed.medA, scheduledAt: Fixed.date(2026, 8, 2, 21),
                      status: .skipped, skipReason: "졸려서 그냥 잤어요", quantity: 1)
        ]

        let remaining = InventoryCalculator.remaining(
            for: Fixed.medA, stockEvents: stock, doseEvents: doses, asOf: Fixed.date(2026, 8, 4)
        )
        XCTAssertEqual(remaining, 10, "건너뜀은 약이 실제로 줄지 않으므로 차감하지 않는다")
    }

    func testUnrecordedDoesNotSubtract() {
        let stock: [StockEvent] = [
            .refill(medicationID: Fixed.medA, quantity: 10, at: Fixed.date(2026, 8, 1))
        ]
        let doses = [
            DoseEvent(medicationID: Fixed.medA, scheduledAt: Fixed.date(2026, 8, 2, 21), status: .unrecorded)
        ]

        let remaining = InventoryCalculator.remaining(
            for: Fixed.medA, stockEvents: stock, doseEvents: doses, asOf: Fixed.date(2026, 8, 4)
        )
        XCTAssertEqual(remaining, 10, "미기록은 '모름'이지 '안 먹음'이 아니다")
    }

    func testRefillsAccumulate() {
        let stock: [StockEvent] = [
            .refill(medicationID: Fixed.medA, quantity: 28, at: Fixed.date(2026, 8, 1)),
            .refill(medicationID: Fixed.medA, quantity: 14, at: Fixed.date(2026, 8, 10))
        ]

        let remaining = InventoryCalculator.remaining(
            for: Fixed.medA, stockEvents: stock, doseEvents: [], asOf: Fixed.date(2026, 8, 11)
        )
        XCTAssertEqual(remaining, 42)
    }

    // MARK: - 정정이 기준점을 다시 세운다

    func testCorrectionResetsBaseline() {
        let stock: [StockEvent] = [
            .refill(medicationID: Fixed.medA, quantity: 28, at: Fixed.date(2026, 8, 1)),
            .correction(medicationID: Fixed.medA, setTo: 17, at: Fixed.date(2026, 8, 10), note: "세어보니 17개")
        ]
        let doses = [
            DoseEvent(medicationID: Fixed.medA, scheduledAt: Fixed.date(2026, 8, 11, 21), status: .taken, quantity: 1),
            DoseEvent(medicationID: Fixed.medA, scheduledAt: Fixed.date(2026, 8, 12, 21), status: .taken, quantity: 1)
        ]

        let remaining = InventoryCalculator.remaining(
            for: Fixed.medA, stockEvents: stock, doseEvents: doses, asOf: Fixed.date(2026, 8, 13)
        )
        XCTAssertEqual(remaining, 15)
    }

    func testEventsBeforeCorrectionAreIgnored() {
        let stock: [StockEvent] = [
            .refill(medicationID: Fixed.medA, quantity: 999, at: Fixed.date(2026, 7, 1)),
            .correction(medicationID: Fixed.medA, setTo: 5, at: Fixed.date(2026, 8, 10))
        ]
        // 정정 이전의 복용은 이미 정정값에 반영되어 있으므로 다시 빼면 안 된다.
        let doses = (1...20).map { day in
            DoseEvent(medicationID: Fixed.medA, scheduledAt: Fixed.date(2026, 7, day, 21), status: .taken, quantity: 1)
        }

        let remaining = InventoryCalculator.remaining(
            for: Fixed.medA, stockEvents: stock, doseEvents: doses, asOf: Fixed.date(2026, 8, 13)
        )
        XCTAssertEqual(remaining, 5)
    }

    func testCorrectionThenRefillAtSameInstantAppliesCorrectionFirst() {
        let sameMoment = Fixed.date(2026, 8, 10, 14, 0)
        let stock: [StockEvent] = [
            .refill(medicationID: Fixed.medA, quantity: 28, at: sameMoment),
            .correction(medicationID: Fixed.medA, setTo: 3, at: sameMoment)
        ]

        let remaining = InventoryCalculator.remaining(
            for: Fixed.medA, stockEvents: stock, doseEvents: [], asOf: Fixed.date(2026, 8, 11)
        )
        XCTAssertEqual(remaining, 31, "같은 시각이면 정정이 기준을 세우고 그 위에 보충이 얹힌다")
    }

    // MARK: - 반 알

    func testHalfTabletSubtraction() {
        let stock: [StockEvent] = [
            .refill(medicationID: Fixed.medA, quantity: 10, at: Fixed.date(2026, 8, 1))
        ]
        let doses = (2...4).map { day in
            DoseEvent(medicationID: Fixed.medA, scheduledAt: Fixed.date(2026, 8, day, 21),
                      status: .taken, quantity: Fixed.decimal("0.5"))
        }

        let remaining = InventoryCalculator.remaining(
            for: Fixed.medA, stockEvents: stock, doseEvents: doses, asOf: Fixed.date(2026, 8, 5)
        )
        XCTAssertEqual(remaining, Fixed.decimal("8.5"))
    }

    func testQuarterStepIsPreservedWithoutFloatingPointDrift() {
        let stock: [StockEvent] = [
            .refill(medicationID: Fixed.medA, quantity: 10, at: Fixed.date(2026, 8, 1))
        ]
        // 0.25 를 40번 빼면 정확히 0 이 되어야 한다. Double 이었다면 여기서 어긋난다.
        let doses = (1...40).map { index in
            DoseEvent(medicationID: Fixed.medA,
                      scheduledAt: Fixed.date(2026, 8, 2, 0, index),
                      status: .taken,
                      quantity: DecimalQuantity.step)
        }

        let remaining = InventoryCalculator.remaining(
            for: Fixed.medA, stockEvents: stock, doseEvents: doses, asOf: Fixed.date(2026, 8, 3)
        )
        XCTAssertEqual(remaining, 0)
        XCTAssertEqual(DecimalQuantity.display(remaining), "0")
    }

    func testSnapToQuarterRoundsToNearestAllowedStep() {
        XCTAssertEqual(DecimalQuantity.snapToQuarter(Fixed.decimal("0.5")), Fixed.decimal("0.5"))
        XCTAssertEqual(DecimalQuantity.snapToQuarter(Fixed.decimal("0.3")), Fixed.decimal("0.25"))
        XCTAssertEqual(DecimalQuantity.snapToQuarter(Fixed.decimal("1.13")), Fixed.decimal("1.25"))
        XCTAssertTrue(DecimalQuantity.isQuarterAligned(Fixed.decimal("1.75")))
        XCTAssertFalse(DecimalQuantity.isQuarterAligned(Fixed.decimal("1.1")))
    }

    // MARK: - 범위와 격리

    func testFutureEventsAreNotCounted() {
        let stock: [StockEvent] = [
            .refill(medicationID: Fixed.medA, quantity: 10, at: Fixed.date(2026, 8, 1)),
            .refill(medicationID: Fixed.medA, quantity: 30, at: Fixed.date(2026, 9, 1))
        ]
        let doses = [
            DoseEvent(medicationID: Fixed.medA, scheduledAt: Fixed.date(2026, 9, 5, 21), status: .taken, quantity: 1)
        ]

        let remaining = InventoryCalculator.remaining(
            for: Fixed.medA, stockEvents: stock, doseEvents: doses, asOf: Fixed.date(2026, 8, 17)
        )
        XCTAssertEqual(remaining, 10)
    }

    func testOtherMedicationsDoNotLeakIn() {
        let stock: [StockEvent] = [
            .refill(medicationID: Fixed.medA, quantity: 10, at: Fixed.date(2026, 8, 1)),
            .refill(medicationID: Fixed.medB, quantity: 99, at: Fixed.date(2026, 8, 1))
        ]
        let doses = [
            DoseEvent(medicationID: Fixed.medB, scheduledAt: Fixed.date(2026, 8, 2, 21), status: .taken, quantity: 5)
        ]

        let remaining = InventoryCalculator.remaining(
            for: Fixed.medA, stockEvents: stock, doseEvents: doses, asOf: Fixed.date(2026, 8, 17)
        )
        XCTAssertEqual(remaining, 10)
    }

    func testActualTimeDecidesWhetherDoseIsCounted() {
        let stock: [StockEvent] = [
            .refill(medicationID: Fixed.medA, quantity: 10, at: Fixed.date(2026, 8, 1))
        ]
        // 8/16 예정분을 8/18 에 뒤늦게 기록했다면, 8/17 시점 잔여에는 아직 반영되지 않는다.
        let doses = [
            DoseEvent(medicationID: Fixed.medA,
                      scheduledAt: Fixed.date(2026, 8, 16, 21),
                      actualAt: Fixed.date(2026, 8, 18, 9),
                      status: .taken,
                      quantity: 1)
        ]

        XCTAssertEqual(
            InventoryCalculator.remaining(for: Fixed.medA, stockEvents: stock,
                                          doseEvents: doses, asOf: Fixed.date(2026, 8, 17, 23)),
            10
        )
        XCTAssertEqual(
            InventoryCalculator.remaining(for: Fixed.medA, stockEvents: stock,
                                          doseEvents: doses, asOf: Fixed.date(2026, 8, 19)),
            9
        )
    }

    // MARK: - 문서의 예시 그대로

    func testWorkedExampleRemainingIsFourteen() {
        let remaining = InventoryCalculator.remaining(
            for: Fixed.medA,
            stockEvents: Fixed.workedExampleStock(),
            doseEvents: Fixed.workedExampleDoses(),
            asOf: Fixed.date(2026, 8, 17, 23, 0)
        )
        XCTAssertEqual(remaining, 14, "8/1 28정 → 8/17 까지 14회 복용 → 14정 남음")
    }
}
