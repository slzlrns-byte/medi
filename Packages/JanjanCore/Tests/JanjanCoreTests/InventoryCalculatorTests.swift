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

    // MARK: - 복약률의 기기 간 중복

    func testAdherenceCollapsesDuplicateEventsAcrossDevices() {
        // 워치와 폰이 오프라인에서 같은 시간대를 서로 다르게 적은 뒤 동기화됐다.
        // remaining() 과 같은 규칙: 가장 나중 것 하나만 세야 한다.
        let earlier = DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 8, 16, 8),
            actualAt: Fixed.date(2026, 8, 16, 8, 5),
            status: .skipped,
            slotKey: "morning"
        )
        let later = DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 8, 16, 8),
            actualAt: Fixed.date(2026, 8, 16, 9, 0),
            status: .taken,
            slotKey: "morning"
        )
        let otherDay = DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 8, 17, 8),
            actualAt: Fixed.date(2026, 8, 17, 8, 5),
            status: .taken,
            slotKey: "morning"
        )

        let rate = InventoryCalculator.adherenceRate(
            doseEvents: [earlier, later, otherDay],
            from: Fixed.date(2026, 8, 10),
            to: Fixed.date(2026, 8, 18)
        )
        // 중복을 안 묶으면 2/3(66%)가 나온다. 묶으면 2/2 = 100%.
        XCTAssertEqual(rate, 1)
    }

    // MARK: - 받아 온 개수

    func testLastRefillQuantityPicksTheMostRecentRefill() {
        let stock: [StockEvent] = [
            .refill(medicationID: Fixed.medA, quantity: 28, at: Fixed.date(2026, 7, 1)),
            .refill(medicationID: Fixed.medA, quantity: 14, at: Fixed.date(2026, 8, 1)),
            // 정정은 보충이 아니다. 더 나중이어도 "받아 온 개수" 가 되면 안 된다.
            .correction(medicationID: Fixed.medA, setTo: 9, at: Fixed.date(2026, 8, 10)),
            // 다른 약의 보충은 섞이면 안 된다.
            .refill(medicationID: Fixed.medB, quantity: 56, at: Fixed.date(2026, 8, 12))
        ]

        XCTAssertEqual(StockEvent.lastRefillQuantity(of: Fixed.medA, in: stock), 14)
        XCTAssertEqual(StockEvent.lastRefillQuantity(of: Fixed.medB, in: stock), 56)
    }

    func testLastRefillQuantityIsNilWithoutAnyRefill() {
        let stock: [StockEvent] = [
            .correction(medicationID: Fixed.medA, setTo: 5, at: Fixed.date(2026, 8, 10))
        ]
        XCTAssertNil(StockEvent.lastRefillQuantity(of: Fixed.medA, in: stock))
        XCTAssertNil(StockEvent.lastRefillQuantity(of: Fixed.medB, in: []))
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

    func testAdherenceIgnoresAsNeededDoses() {
        // 정기 2건(복용 1·건너뜀 1) 사이에 필요시 복용이 아무리 섞여도
        // 복약률은 정기만 본다: 1/2 = 50%.
        let day1 = Fixed.date(2026, 8, 10, 8, 0)
        let day2 = Fixed.date(2026, 8, 11, 8, 0)
        var events = [
            DoseEvent(
                medicationID: Fixed.medA, scheduledAt: day1, actualAt: day1,
                status: .taken, quantity: 1, slotKey: DoseSlot.morning.storageKey
            ),
            DoseEvent(
                medicationID: Fixed.medA, scheduledAt: day2, actualAt: nil,
                status: .skipped, quantity: 1, slotKey: DoseSlot.morning.storageKey
            )
        ]
        for hour in [10, 15, 21] {
            let at = Fixed.date(2026, 8, 10, hour, 0)
            events.append(DoseEvent(
                medicationID: Fixed.medA, scheduledAt: at, actualAt: at,
                status: .taken, quantity: 1, kind: .asNeeded, slotKey: nil
            ))
        }
        let rate = InventoryCalculator.adherenceRate(
            doseEvents: events,
            medicationID: Fixed.medA,
            from: Fixed.date(2026, 8, 9),
            to: Fixed.date(2026, 8, 12),
            calendar: Fixed.calendar
        )
        XCTAssertEqual(rate, Decimal(string: "0.5"))
    }

    // MARK: - 이번 구간 (총량 · 소비량)

    func testCycleStatusAfterRefill() {
        // 정정 17 + 같은 날 보충 28 → 구간 총량 45. 이후 3정 복용 → 소비 3, 잔여 42.
        let visit = Fixed.date(2026, 8, 10)
        let stock: [StockEvent] = [
            .correction(medicationID: Fixed.medA, setTo: 17, at: visit, note: "진료일에 세어 둠"),
            .refill(medicationID: Fixed.medA, quantity: 28, at: visit)
        ]
        var doses: [DoseEvent] = []
        for day in 11...13 {
            let at = Fixed.date(2026, 8, day, 21)
            doses.append(DoseEvent(medicationID: Fixed.medA, scheduledAt: at, status: .taken, quantity: 1))
        }

        let cycle = InventoryCalculator.cycleStatus(
            for: Fixed.medA, stockEvents: stock, doseEvents: doses, asOf: Fixed.date(2026, 8, 14)
        )
        XCTAssertEqual(cycle?.total, 45, "구간 총량 = 정정으로 세운 기준 + 같은 시각의 보충")
        XCTAssertEqual(cycle?.consumed, 3)

        let remaining = InventoryCalculator.remaining(
            for: Fixed.medA, stockEvents: stock, doseEvents: doses, asOf: Fixed.date(2026, 8, 14)
        )
        XCTAssertEqual((cycle?.total ?? 0) - (cycle?.consumed ?? 0), remaining,
                       "화면의 세 숫자(총량·소비·잔여)는 늘 맞아떨어져야 한다")
    }

    func testCycleStatusWithoutStockEventsIsNil() {
        let cycle = InventoryCalculator.cycleStatus(
            for: Fixed.medA, stockEvents: [], doseEvents: [], asOf: Fixed.date(2026, 8, 14)
        )
        XCTAssertNil(cycle, "재고를 한 번도 세지 않았으면 총량을 지어내지 않는다")
    }
}

// MARK: - 진료 기록 삭제 (QA 2026-09-21)

extension InventoryCalculatorTests {

    /// 진료를 지울 때 보충만 걷고 "받기 전 남은 개수"(정정)를 남기면, 남은
    /// 정정이 **받기 전** 수라서 기준점이 그대로 서고 재고가 음수로 내려간다.
    /// 9/1 에 4정 세고 28정 받아 20일 먹은 사람은 12정이 맞다.
    func testVisitDayCorrectionCarriesThePrescriptionID() {
        let prescriptionID = UUID()
        let visit = Fixed.date(2026, 9, 1)

        let correction = StockEvent.correction(
            medicationID: Fixed.medA,
            setTo: 4,
            at: visit,
            prescriptionID: prescriptionID,
            note: "진료일에 세어 둔 개수"
        )
        let refill = StockEvent.refill(
            medicationID: Fixed.medA,
            quantity: 28,
            at: visit,
            prescriptionID: prescriptionID
        )

        // 한 사건의 두 쪽이라 같은 처방에 매인다 - 이게 어긋나면 삭제가
        // 보충만 걷어 가고 기준점을 남긴다.
        XCTAssertEqual(correction.prescriptionID, prescriptionID)
        XCTAssertEqual(refill.prescriptionID, prescriptionID)

        let doses = (1...20).map { offset in
            DoseEvent(
                medicationID: Fixed.medA,
                scheduledAt: Fixed.date(2026, 9, 1 + offset, 9),
                actualAt: Fixed.date(2026, 9, 1 + offset, 9),
                status: .taken,
                quantity: 1,
                kind: .scheduled,
                slotKey: "morning"
            )
        }

        XCTAssertEqual(
            InventoryCalculator.remaining(
                for: Fixed.medA,
                stockEvents: [correction, refill],
                doseEvents: doses,
                asOf: Fixed.date(2026, 9, 21, 23),
                calendar: Fixed.calendar
            ),
            12
        )

        // 처방으로 걸러 지우면 그 약의 재고 사건이 하나도 남지 않는다.
        let survivors = [correction, refill].filter { event in
            guard let owner = event.prescriptionID else { return true }
            return owner != prescriptionID
        }
        XCTAssertTrue(survivors.isEmpty)
    }

    /// 기기 둘이 같은 칸에 기록한 날이 있으면, 종이의 "복용 N회" 도
    /// 복약률과 같은 집합에서 세야 한 칸에 두 숫자가 어긋나지 않는다.
    func testCollapsedScheduledDosesMergesCrossDeviceDuplicates() {
        let slot = "morning"
        let scheduled = Fixed.date(2026, 9, 2, 8)
        let duplicates = [
            DoseEvent(medicationID: Fixed.medA, scheduledAt: scheduled,
                      status: .skipped, quantity: 1, kind: .scheduled, slotKey: slot),
            DoseEvent(medicationID: Fixed.medA, scheduledAt: scheduled,
                      actualAt: Fixed.date(2026, 9, 2, 8, 5),
                      status: .taken, quantity: 1, kind: .scheduled, slotKey: slot)
        ]

        let collapsed = InventoryCalculator.collapsedScheduledDoses(
            duplicates, calendar: Fixed.calendar
        )
        XCTAssertEqual(collapsed.count, 1)
        XCTAssertEqual(collapsed.first?.status, .taken, "가장 나중 것이 남는다")

        // 필요시 약은 묶지 않는다 - 하루에 두 번 먹었으면 두 번이 사실이다.
        let asNeeded = [
            DoseEvent(medicationID: Fixed.medB, scheduledAt: scheduled,
                      status: .taken, quantity: 1, kind: .asNeeded),
            DoseEvent(medicationID: Fixed.medB, scheduledAt: scheduled,
                      status: .taken, quantity: 1, kind: .asNeeded)
        ]
        XCTAssertEqual(
            InventoryCalculator.collapsedScheduledDoses(asNeeded, calendar: Fixed.calendar).count,
            0,
            "정기분만 다룬다"
        )
    }
}

// MARK: - 기준점이 없을 때 (QA 2026-09-21)

extension InventoryCalculatorTests {

    /// 재고 칸을 비우고 등록하면 정정이 생기지 않는다. 그때 셈이 0 에서
    /// 시작해 그 앞의 복용까지 빼면 남은 개수가 음수로 내려간다.
    ///
    /// 8/1 등록(재고 안 셈) → 8/1~8/30 매일 1정 → 8/31 에 28정 받음.
    /// 앱이 개수를 처음 안 것은 8/31 이므로, 그 앞의 30정은 앱이 존재조차
    /// 모르던 약이다. 남은 개수는 28정이어야 한다(−2정이 아니라).
    func testFirstStockEventIsTheBaselineWhenNothingWasCounted() {
        let doses = (1...30).map { day in
            DoseEvent(
                medicationID: Fixed.medA,
                scheduledAt: Fixed.date(2026, 8, day, 21),
                actualAt: Fixed.date(2026, 8, day, 21),
                status: .taken,
                quantity: 1,
                kind: .scheduled,
                slotKey: DoseSlot.bedtime.storageKey
            )
        }
        let stock: [StockEvent] = [
            .refill(medicationID: Fixed.medA, quantity: 28, at: Fixed.date(2026, 8, 31, 10))
        ]

        XCTAssertEqual(
            InventoryCalculator.remaining(
                for: Fixed.medA,
                stockEvents: stock,
                doseEvents: doses,
                asOf: Fixed.date(2026, 8, 31, 23),
                calendar: Fixed.calendar
            ),
            28
        )
    }

    /// 기준점이 생긴 **뒤**의 복용은 그대로 뺀다.
    func testDosesAfterTheFirstStockEventStillSubtract() {
        let stock: [StockEvent] = [
            .refill(medicationID: Fixed.medA, quantity: 28, at: Fixed.date(2026, 8, 1, 10))
        ]
        let doses = (2...6).map { day in
            DoseEvent(
                medicationID: Fixed.medA,
                scheduledAt: Fixed.date(2026, 8, day, 21),
                actualAt: Fixed.date(2026, 8, day, 21),
                status: .taken,
                quantity: 1,
                kind: .scheduled,
                slotKey: DoseSlot.bedtime.storageKey
            )
        }

        XCTAssertEqual(
            InventoryCalculator.remaining(
                for: Fixed.medA,
                stockEvents: stock,
                doseEvents: doses,
                asOf: Fixed.date(2026, 8, 10),
                calendar: Fixed.calendar
            ),
            23
        )
    }

    /// 정정이 있으면 예전 규칙 그대로다 - 정정이 기준점이고 그 앞은 버린다.
    func testCorrectionStillWinsAsTheBaseline() {
        let stock: [StockEvent] = [
            .refill(medicationID: Fixed.medA, quantity: 28, at: Fixed.date(2026, 8, 1, 10)),
            // 그날 21시 복용보다 **뒤**에 맞춘다. 낮에 맞추면 그날 저녁 약이
            // 정정 뒤로 들어가 한 알 더 빠진다.
            .correction(medicationID: Fixed.medA, setTo: 10, at: Fixed.date(2026, 8, 10, 23))
        ]
        let doses = (2...20).map { day in
            DoseEvent(
                medicationID: Fixed.medA,
                scheduledAt: Fixed.date(2026, 8, day, 21),
                actualAt: Fixed.date(2026, 8, day, 21),
                status: .taken,
                quantity: 1,
                kind: .scheduled,
                slotKey: DoseSlot.bedtime.storageKey
            )
        }

        // 8/10 에 10정으로 맞췄고 그 뒤 8/11~8/20 에 10정을 먹었다 → 0.
        XCTAssertEqual(
            InventoryCalculator.remaining(
                for: Fixed.medA,
                stockEvents: stock,
                doseEvents: doses,
                asOf: Fixed.date(2026, 8, 25),
                calendar: Fixed.calendar
            ),
            0
        )
    }
}
