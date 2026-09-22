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

    /// **분자도 분모가 선 날들만 본다.** 28일치를 받고 40일이 지났으면,
    /// 분모는 28일치에서 멈추고 분자도 그 28일 안의 기록만 센다. 예전에는
    /// 분자만 계속 자라 "받은 28정 예정 중 복용 기록 40정" 이 찍혔고
    /// 비율이 100% 에 붙어 버렸다(QA 2026-09-21).
    func testTakenDoesNotKeepGrowingPastTheSupply() {
        // 9/1 에 28일치. 앞 14일은 다 먹고, 처방이 끝난 뒤로도 계속 먹었다.
        let after = (1...12).map { day -> DoseEvent in
            let at = Fixed.date(2026, 10, day, 8, 0)
            return DoseEvent(
                medicationID: Fixed.medA,
                scheduledAt: at,
                actualAt: at,
                status: .taken,
                quantity: 1,
                kind: .scheduled,
                slotKey: DoseSlot.morning.storageKey
            )
        }
        let result = rate(
            doses: (1...14).map { taken(day: $0) } + after,
            asOf: Fixed.date(2026, 10, 12, 23, 0)
        )

        XCTAssertEqual(result?.expected, 28)
        XCTAssertEqual(result?.taken, 14, "처방 기간 밖의 복용은 분자에 들어가지 않는다")
        XCTAssertEqual(result?.rate, Decimal(string: "0.5"))
    }

    /// **앱을 깔기 전의 날은 분모에 넣지 않는다**(QA 2026-09-22).
    ///
    /// 오늘 앱을 깔고 지난 진료를 적는 사람이 있다. `DayPlan` 은 등록일 앞에
    /// 계획을 만들지 않으므로 그 날들에는 복용 기록이 **있을 수가 없다**.
    /// 그대로 세면 한 알도 안 빠트린 사람의 첫 리포트가 0% 로 나간다.
    func testDaysBeforeTheAppKnewTheMedicationAreNotCounted() {
        // 9/1 진료(28일치 28정)를 9/15 에 앱을 깔고 적었다. 9/15~9/20 은
        // 꼬박 먹었다(9/21 은 아직 안 지났다).
        var registered = medication()
        registered.createdAt = Fixed.date(2026, 9, 15, 9, 0)
        let result = rate(
            doses: (15...20).map { taken(day: $0) },
            medications: [registered]
        )
        // 분모는 9/15~9/20 의 6일치 = 28 × 6 ÷ 28 = 6정.
        XCTAssertEqual(result?.expected, 6, "등록 전 14일은 분모에 없다")
        XCTAssertEqual(result?.taken, 6)
        XCTAssertEqual(result?.rate, 1, "꼬박 먹었으면 100% 다")
    }

    /// 등록일이 없는 옛 기록은 예전처럼 진료일부터 센다.
    func testMedicationWithoutACreatedAtIsUnchanged() {
        XCTAssertEqual(rate(doses: (2...19).map { taken(day: $0) })?.expected, 20)
    }

    /// **분자도 달력과 같은 축을 쓴다**(QA 2026-09-22).
    ///
    /// 어젯밤 취침약을 자정 넘겨 누르면 `actualAt` 은 다음 날이 된다. 그것으로
    /// 창을 자르면 창 끝의 한 알이 밀려 나가, 하루도 안 빠트린 사람이 96% 가
    /// 됐다. 달력이 그 기록을 어제의 줄로 그리는 것처럼 여기도 `scheduledAt`
    /// 으로 자른다.
    func testADoseLoggedAfterMidnightStillCountsForItsOwnDay() {
        // 창의 마지막 날(9/20) 취침약을 9/21 00:10 에 눌렀다.
        let lateNight = DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 9, 20, 22, 30),
            actualAt: Fixed.date(2026, 9, 21, 0, 10),
            status: .taken,
            quantity: 1,
            kind: .scheduled,
            slotKey: DoseSlot.bedtime.storageKey
        )
        let result = rate(doses: (2...19).map { taken(day: $0) } + [lateNight])
        XCTAssertEqual(result?.taken, 19, "예정 시각이 9/20 이면 9/20 의 약이다")
    }

    /// 더 먹었다고 100% 를 넘겨 적지 않는다.
    func testRateNeverExceedsOneHundred() {
        let doses = (2...21).map { taken(day: $0, quantity: 2) }   // 예정의 두 배
        XCTAssertEqual(rate(doses: doses)?.rate, 1)
    }
}

// MARK: - 약별 평균 (사용자 결정 2026-09-21)

extension PrescriptionAdherenceTests {

    private func twoMedPrescription() -> Prescription {
        Prescription(
            id: prescriptionID,
            visitDate: visitDay,
            daysSupplied: 14,
            medicationIDs: [Fixed.medA, Fixed.medB]
        )
    }

    /// 하나는 꼬박 먹고 하나는 통째로 건너뛰면 **50%** 다.
    ///
    /// 알 수로 가중하면 하루 세 번 먹는 약이 한 번 먹는 약보다 세 배
    /// 무거워진다. 약 두 개 중 하나를 안 먹은 것은 그냥 절반이다.
    func testOverallRateAveragesEachMedication() {
        // 약 A 는 하루 3정(14일에 42정), 약 B 는 하루 1정(14정).
        let stock = [
            refill(42, medicationID: Fixed.medA),
            refill(14, medicationID: Fixed.medB)
        ]
        // 14일(9/1~9/14) 내내 A 만 먹었다.
        let doses = (1...14).map { taken(day: $0, quantity: 3, medicationID: Fixed.medA) }

        let result = InventoryCalculator.prescriptionAdherence(
            prescriptions: [twoMedPrescription()],
            stockEvents: stock,
            doseEvents: doses,
            medications: [medication(), medication(id: Fixed.medB)],
            asOf: Fixed.date(2026, 9, 15, 23, 0),
            calendar: calendar
        )

        XCTAssertEqual(result?.items.count, 2)
        XCTAssertEqual(result?.rate, Decimal(string: "0.5"), "100% 와 0% 의 평균")

        // 알 수로 가중했다면 42/56 = 75% 가 나왔을 것이다.
        XCTAssertNotEqual(result?.rate, Decimal(42) / Decimal(56))
    }

    /// 2주 내내 건너뛰다가 끊은 약은 그 2주에 대해 0% 다.
    /// 끊은 뒤로는 분모가 더 자라지 않는다.
    func testStoppedMedicationCountsUpToTheDayItStopped() {
        var stopped = medication(id: Fixed.medB)
        stopped.status = .stopped
        stopped.stoppedAt = Fixed.date(2026, 9, 15, 12, 0)   // 14일 뒤

        let stock = [
            refill(28, medicationID: Fixed.medA),
            refill(28, medicationID: Fixed.medB)
        ]
        // A 만 꼬박 먹었다(9/1~9/28). B 는 한 번도 안 먹고 9/15 에 끊었다.
        let doses = (1...28).map { taken(day: $0, medicationID: Fixed.medA) }

        let result = InventoryCalculator.prescriptionAdherence(
            prescriptions: [prescription()],
            stockEvents: stock,
            doseEvents: doses,
            medications: [medication(), stopped],
            asOf: Fixed.date(2026, 9, 29, 23, 0),
            calendar: calendar
        )

        let b = result?.items.first { $0.medicationID == Fixed.medB }
        XCTAssertEqual(b?.rate, 0, "2주 내내 건너뛴 약은 0% 다")
        // 끊은 날까지 14일치 = 28 × 14/28 = 14정.
        XCTAssertEqual(b?.expected, 14, "끊은 뒤로는 분모가 자라지 않는다")

        let a = result?.items.first { $0.medicationID == Fixed.medA }
        XCTAssertEqual(a?.rate, 1)
        XCTAssertEqual(result?.rate, Decimal(string: "0.5"))
    }

    /// 진료 당일에 끊은 약은 셀 것이 없어 아예 빠진다.
    func testMedicationStoppedOnTheVisitDayIsLeftOut() {
        var stopped = medication(id: Fixed.medB)
        stopped.status = .stopped
        stopped.stoppedAt = visitDay

        let result = InventoryCalculator.prescriptionAdherence(
            prescriptions: [prescription()],
            stockEvents: [refill(28), refill(28, medicationID: Fixed.medB)],
            doseEvents: (2...19).map { taken(day: $0) },
            medications: [medication(), stopped],
            asOf: Fixed.date(2026, 9, 21, 23, 0),
            calendar: calendar
        )
        XCTAssertEqual(result?.items.count, 1)
        XCTAssertEqual(result?.rate, Decimal(string: "0.9"))
    }
}

// MARK: - 다녀온 진료와 일정만 담은 기록 (사용자 지적 2026-09-22)

final class ScheduleOnlyPrescriptionTests: XCTestCase {

    private let day = Fixed.date(2026, 9, 10, 10)

    /// 오늘 탭의 "다음 진료" 칩이 만드는 모양. 두 날짜가 같은 하나다.
    func testScheduleChipRecordIsNotAVisit() {
        let record = Prescription(visitDate: day, daysSupplied: 0, nextVisitDate: day)
        XCTAssertTrue(record.isScheduleOnly)
    }

    /// **이것이 이 규칙을 고친 이유다.** 진료 기록 화면에서 약을 고르지 않고
    /// 처방일수와 메모를 비운 채 저장해도 기록은 비어 보인다. 예전 규칙은
    /// 그것까지 가짜로 보아 지난 진료 기록·리포트에서 통째로 지웠다.
    func testAVisitSavedWithNothingFilledInIsStillAVisit() {
        let saved = Prescription(visitDate: day, daysSupplied: 0)
        XCTAssertFalse(saved.isScheduleOnly, "다음 진료를 안 잡은 진료는 진료다")

        let withNextVisit = Prescription(
            visitDate: day,
            daysSupplied: 0,
            nextVisitDate: Fixed.date(2026, 10, 8, 10)
        )
        XCTAssertFalse(withNextVisit.isScheduleOnly, "다음 진료일이 다르면 진료다")
    }

    func testAnythingFilledInMakesItAVisit() {
        XCTAssertFalse(
            Prescription(visitDate: day, daysSupplied: 28, nextVisitDate: day).isScheduleOnly
        )
        XCTAssertFalse(
            Prescription(visitDate: day, daysSupplied: 0, nextVisitDate: day, clinicNote: "용량 늘림")
                .isScheduleOnly
        )
        XCTAssertFalse(
            Prescription(visitDate: day, daysSupplied: 0, nextVisitDate: day, medicationIDs: [Fixed.medA])
                .isScheduleOnly
        )
    }

    /// 공백만 적은 메모는 적지 않은 것과 같다.
    func testWhitespaceNoteIsStillEmpty() {
        let record = Prescription(visitDate: day, daysSupplied: 0, nextVisitDate: day, clinicNote: "   ")
        XCTAssertTrue(record.isScheduleOnly)
    }
}

// MARK: - 진료 폴백과 창 (QA 2026-09-22)

final class PrescriptionFallbackTests: XCTestCase {

    private let calendar = Fixed.calendar

    private func taken(_ month: Int, _ day: Int) -> DoseEvent {
        let at = Fixed.date(2026, month, day, 8, 0)
        return DoseEvent(
            medicationID: Fixed.medA, scheduledAt: at, actualAt: at,
            status: .taken, quantity: 1, kind: .scheduled,
            slotKey: DoseSlot.morning.storageKey
        )
    }

    /// 진료실에서 오늘 진료를 먼저 적고 리포트를 뽑는다. 오늘 진료는 셀 날이
    /// 없으니 건너뛰고 지난 진료로 센다 - 그리고 그 진료가 창의 기준이다.
    func testVisitTodayFallsBackToThePreviousVisitAndItsWindow() {
        let earlier = Prescription(visitDate: Fixed.date(2026, 9, 1, 10), daysSupplied: 28)
        let today = Prescription(visitDate: Fixed.date(2026, 9, 22, 10), daysSupplied: 28)
        let stock = [
            StockEvent.refill(medicationID: Fixed.medA, quantity: 28,
                              at: earlier.visitDate, prescriptionID: earlier.id),
            StockEvent.refill(medicationID: Fixed.medA, quantity: 28,
                              at: today.visitDate, prescriptionID: today.id)
        ]
        let result = InventoryCalculator.prescriptionAdherence(
            prescriptions: [earlier, today],
            stockEvents: stock,
            doseEvents: (1...21).map { taken(9, $0) } + [taken(9, 22)],
            medications: [Medication(id: Fixed.medA, name: "A")],
            asOf: Fixed.date(2026, 9, 22, 23, 0),
            calendar: calendar
        )
        XCTAssertEqual(result?.visitDate, earlier.visitDate, "오늘 진료는 건너뛴다")
        XCTAssertEqual(result?.windowStart, Fixed.date(2026, 9, 1, 0))
        XCTAssertEqual(result?.windowEnd, Fixed.date(2026, 9, 22, 0), "오늘은 창 밖이다")
        XCTAssertEqual(result?.taken, 21, "오늘 아침 한 알은 분자에 안 든다")
        XCTAssertEqual(result?.rate, 1)
    }

    /// 마지막 진료의 약을 지웠으면(보충이 없으면) 그 앞 진료로 물러난다.
    func testVisitWithoutRefillsIsSkipped() {
        let earlier = Prescription(visitDate: Fixed.date(2026, 8, 1, 10), daysSupplied: 28)
        let later = Prescription(visitDate: Fixed.date(2026, 9, 1, 10), daysSupplied: 28)
        let stock = [
            StockEvent.refill(medicationID: Fixed.medA, quantity: 28,
                              at: earlier.visitDate, prescriptionID: earlier.id)
        ]
        let result = InventoryCalculator.prescriptionAdherence(
            prescriptions: [earlier, later],
            stockEvents: stock,
            doseEvents: (1...28).map { taken(8, $0) },
            medications: [Medication(id: Fixed.medA, name: "A")],
            asOf: Fixed.date(2026, 9, 22, 23, 0),
            calendar: calendar
        )
        XCTAssertEqual(result?.visitDate, earlier.visitDate)
        XCTAssertEqual(result?.expected, 28)
        XCTAssertEqual(result?.taken, 28)
    }
}
