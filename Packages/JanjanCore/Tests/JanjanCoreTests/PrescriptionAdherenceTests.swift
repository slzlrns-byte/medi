import XCTest
@testable import JanjanCore

/// 복약률은 **받은 약**으로 센다(사용자 결정 2026-09-21).
///
/// 예전에는 시간대 칸을 셌는데, 그 예정은 저장해 둔 것이 아니라 지금의
/// 요일로 매번 다시 그린 것이라 요일을 고치기만 해도 지난 숫자가 흔들렸다.
/// 진료에서 받은 알 수는 저장된 사실이라 그런 일이 없다.
final class PrescriptionAdherenceTests: XCTestCase {

    private let calendar = Fixed.calendar
    private let visitDay = Fixed.date(2026, 9, 1, 10, 0)
    private let prescriptionID = UUID()

    private func prescription(daysSupplied: Int = 28) -> Prescription {
        Prescription(
            id: prescriptionID,
            visitDate: visitDay,
            daysSupplied: daysSupplied,
            medicationIDs: [Fixed.medA]
        )
    }

    private func refill(_ quantity: Decimal, medicationID: UUID = Fixed.medA) -> StockEvent {
        .refill(
            medicationID: medicationID,
            quantity: quantity,
            at: visitDay,
            prescriptionID: prescriptionID
        )
    }

    private func taken(day: Int, quantity: Decimal = 1, medicationID: UUID = Fixed.medA) -> DoseEvent {
        let at = Fixed.date(2026, 9, day, 8, 0)
        return DoseEvent(
            medicationID: medicationID,
            scheduledAt: at,
            actualAt: at,
            status: .taken,
            quantity: quantity,
            kind: .scheduled,
            slotKey: DoseSlot.morning.storageKey
        )
    }

    private func medication(kind: Medication.Kind = .scheduled, id: UUID = Fixed.medA) -> Medication {
        Medication(id: id, name: "에스시탈로프람", kind: kind)
    }

    private func rate(
        doses: [DoseEvent],
        stock: [StockEvent]? = nil,
        prescriptions: [Prescription]? = nil,
        medications: [Medication]? = nil,
        asOf: Date = Fixed.date(2026, 9, 21, 23, 0)
    ) -> InventoryCalculator.PrescriptionAdherence? {
        InventoryCalculator.prescriptionAdherence(
            prescriptions: prescriptions ?? [prescription()],
            stockEvents: stock ?? [refill(28)],
            doseEvents: doses,
            medications: medications ?? [medication()],
            asOf: asOf,
            calendar: calendar
        )
    }

    // MARK: - 셈

    /// 9/1 에 28일치 28정, 9/21 이면 20일 경과 → 20정 예정. 18정 기록 → 90%.
    func testCountsAgainstWhatWasReceived() {
        let doses = (2...19).map { taken(day: $0) }   // 18일치
        let result = rate(doses: doses)

        XCTAssertEqual(result?.elapsedDays, 20)
        XCTAssertEqual(result?.received, 28)
        XCTAssertEqual(result?.expected, 20)
        XCTAssertEqual(result?.taken, 18)
        XCTAssertEqual(result?.rate, Decimal(string: "0.9"))
    }

    /// **기록하지 않은 날은 안 먹은 것으로 센다.** 분모는 처방이 정하므로
    /// 기록이 없으면 분자에 안 들어갈 뿐이다.
    func testUnrecordedDaysCountAsNotTaken() {
        let result = rate(doses: (2...11).map { taken(day: $0) })   // 10일치만
        XCTAssertEqual(result?.taken, 10)
        XCTAssertEqual(result?.expected, 20)
        XCTAssertEqual(result?.rate, Decimal(string: "0.5"))
    }

    /// 나중에 그 날을 채우면 그때 집계된다.
    func testFillingInLaterRaisesTheRate() {
        let before = rate(doses: (2...11).map { taken(day: $0) })
        let after = rate(doses: (2...19).map { taken(day: $0) })
        XCTAssertEqual(before?.rate, Decimal(string: "0.5"))
        XCTAssertEqual(after?.rate, Decimal(string: "0.9"))
    }

    // MARK: - 요일을 바꿔도 흔들리지 않는다

    /// 이 규칙을 만든 이유. 계획을 다시 그려 미기록이 잔뜩 생겨도, 분모가
    /// 처방에서 나오므로 비율은 그대로다.
    func testWeekdayChangeDoesNotMoveTheRate() {
        let real = (2...19).map { taken(day: $0) }
        // 요일을 넓히면 앱이 채우는 미기록 줄들. 예전 규칙에서는 이것들이
        // 분모로 들어가 100% 를 42% 로 끌어내렸다.
        let filled = (2...19).map { day -> DoseEvent in
            DoseEvent(
                medicationID: Fixed.medA,
                scheduledAt: Fixed.date(2026, 9, day, 21, 0),
                status: .unrecorded,
                source: .automatic,
                quantity: 1,
                kind: .scheduled,
                slotKey: DoseSlot.bedtime.storageKey
            )
        }
        XCTAssertEqual(rate(doses: real)?.rate, rate(doses: real + filled)?.rate)
    }

    // MARK: - 숫자를 지어내지 않는 자리

    func testNoVisitMeansNoRate() {
        XCTAssertNil(rate(doses: [taken(day: 2)], prescriptions: []))
    }

    func testVisitDayItselfHasNothingToCountYet() {
        XCTAssertNil(rate(doses: [], asOf: Fixed.date(2026, 9, 1, 23, 0)))
    }

    func testNoRefillMeansNoRate() {
        XCTAssertNil(rate(doses: [taken(day: 2)], stock: []))
    }

    func testFutureVisitIsNotUsed() {
        let future = Prescription(
            visitDate: Fixed.date(2026, 10, 1),
            daysSupplied: 28,
            medicationIDs: [Fixed.medA]
        )
        // 미래 진료는 고르지 않고, 지난 진료가 있으면 그것으로 센다.
        let result = rate(doses: (2...19).map { taken(day: $0) },
                          prescriptions: [prescription(), future])
        XCTAssertEqual(result?.visitDate, visitDay)
    }

    // MARK: - 빼고 세는 것

    /// 필요시 약은 안 먹는 게 정상이라 분모에 넣으면 비율이 근거 없이 내려간다.
    func testAsNeededMedicationIsLeftOut() {
        let prn = UUID()
        let result = rate(
            doses: (2...19).map { taken(day: $0) },
            stock: [refill(28), refill(10, medicationID: prn)],
            medications: [medication(), medication(kind: .asNeeded, id: prn)]
        )
        XCTAssertEqual(result?.received, 28, "필요시 약 10정은 안 센다")
        XCTAssertEqual(result?.rate, Decimal(string: "0.9"))
    }

    /// 처방일수를 넘겨도 분모가 계속 늘지 않는다 - 받은 약이 그만큼뿐이다.
    func testExpectedStopsAtTheSupplyLength() {
        let result = rate(
            doses: (2...29).map { taken(day: $0) },
            asOf: Fixed.date(2026, 10, 15, 23, 0)
        )
        XCTAssertEqual(result?.expected, 28, "28일치를 넘겨 세지 않는다")
    }

    /// 더 먹었다고 100% 를 넘겨 적지 않는다.
    func testRateNeverExceedsOneHundred() {
        let doses = (2...21).map { taken(day: $0, quantity: 2) }   // 예정의 두 배
        XCTAssertEqual(rate(doses: doses)?.rate, 1)
    }
}
