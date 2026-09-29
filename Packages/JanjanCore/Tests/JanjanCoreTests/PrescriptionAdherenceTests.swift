import XCTest
@testable import JanjanCore

/// 복약률은 **진료 시각부터 지금까지 스케줄이 예정한 개수**로 센다(사용자
/// 결정 2026-09-22). 진료 전 아침 약은 이전 처방의 몫이고, 오늘의 아직 안 온
/// 시간대는 세지 않는다. 받은 알 수는 어느 약이 그 진료에 속하는지 정하는
/// 데만 쓴다.
final class PrescriptionAdherenceTests: XCTestCase {

    private let calendar = Fixed.calendar
    /// 진료는 10시. 그날 8시 아침 약은 이 처방의 몫이 아니다.
    private let visitDay = Fixed.date(2026, 9, 1, 10, 0)
    private let prescriptionID = UUID()

    /// 아침 8시 매일 한 알.
    private func morning(_ medicationID: UUID = Fixed.medA, dose: Decimal = 1) -> Schedule {
        Schedule(medicationID: medicationID, slot: .morning, dosePerIntake: dose)
    }

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
        schedules: [Schedule]? = nil,
        asOf: Date = Fixed.date(2026, 9, 21, 23, 0)
    ) -> InventoryCalculator.PrescriptionAdherence? {
        InventoryCalculator.prescriptionAdherence(
            prescriptions: prescriptions ?? [prescription()],
            schedules: schedules ?? [morning()],
            stockEvents: stock ?? [refill(28)],
            doseEvents: doses,
            medications: medications ?? [medication()],
            asOf: asOf,
            calendar: calendar
        )
    }

    // MARK: - 셈

    /// 9/1 10시 진료, 아침 8시 약. 9/21 밤이면 9/2~9/21 의 20칸이 예정.
    /// 18정 기록 → 90%. (9/1 8시는 진료 전이라 이 처방의 몫이 아니다.)
    func testCountsWhatTheScheduleExpectedSinceTheVisit() {
        let doses = (2...19).map { taken(day: $0) }   // 18일치
        let result = rate(doses: doses)

        XCTAssertEqual(result?.elapsedDays, 20)
        XCTAssertEqual(result?.received, 28)
        XCTAssertEqual(result?.expected, 20)
        XCTAssertEqual(result?.taken, 18)
        XCTAssertEqual(result?.rate, Decimal(string: "0.9"))
    }

    /// **기록하지 않은 칸은 안 먹은 것으로 센다.** 분모는 스케줄이 정하므로
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

    // MARK: - 분모는 스케줄이 정한다

    /// 앱이 채워 넣는 미기록 줄은 분모가 아니다. 분모는 스케줄에서 나오고
    /// 분자는 복용함만 세므로, 그런 줄이 아무리 많아도 비율은 그대로다.
    func testAppFilledUnrecordedRowsDoNotMoveTheRate() {
        let real = (2...19).map { taken(day: $0) }
        // 요일을 넓히면 앱이 채우는 미기록 줄들.
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

    /// 진료 뒤에 지난 시간대가 하나도 없으면 셀 것이 없다. 10시 진료에
    /// 아침 약뿐이면 그날 밤에도 nil 이다.
    func testNoSlotHasPassedSinceTheVisitYet() {
        XCTAssertNil(rate(doses: [], asOf: Fixed.date(2026, 9, 1, 23, 0)))
    }

    /// **진료 당일에도 시간대가 지나면 바로 선다**(사용자 결정 2026-09-22).
    /// 10시 진료 뒤 22:30 자기전 약이 지났으면 그 한 칸이 분모다.
    func testVisitDayCountsOnceASlotAfterTheVisitHasPassed() {
        let bedtime = Schedule(medicationID: Fixed.medA, slot: .bedtime, dosePerIntake: 1)
        let tookIt = DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 9, 1, 22, 30),
            actualAt: Fixed.date(2026, 9, 1, 22, 40),
            status: .taken, quantity: 1, kind: .scheduled,
            slotKey: DoseSlot.bedtime.storageKey
        )
        let before = rate(doses: [], schedules: [morning(), bedtime], asOf: Fixed.date(2026, 9, 1, 15, 0))
        XCTAssertNil(before, "15시에는 진료 뒤 지난 시간대가 없다")

        let after = rate(doses: [tookIt], schedules: [morning(), bedtime], asOf: Fixed.date(2026, 9, 1, 23, 0))
        XCTAssertEqual(after?.expected, 1, "진료 뒤 자기전 한 칸만 분모다")
        XCTAssertEqual(after?.taken, 1)
        XCTAssertEqual(after?.rate, 1)
    }

    /// **오늘의 아직 안 온 시간대는 세지 않는다.** 오후 3시에 보면 자기전
    /// 약은 분모에 없다.
    func testSlotsLaterTodayAreNotExpectedYet() {
        let bedtime = Schedule(medicationID: Fixed.medA, slot: .bedtime, dosePerIntake: 1)
        let afternoon = rate(
            doses: (2...19).map { taken(day: $0) },
            schedules: [morning(), bedtime],
            asOf: Fixed.date(2026, 9, 21, 15, 0)
        )
        // 아침 9/2~9/21 = 20칸, 자기전 9/1~9/20 = 20칸. 9/21 자기전은 아직이다.
        XCTAssertEqual(afternoon?.expected, 40)
    }

    /// **하루 두 번 먹는 약은 스케줄대로 두 번 센다.** 받은 알 수로 나누던
    /// 때는 28정을 받으면 하루치가 1정이었다.
    func testTwiceADayIsExpectedTwiceADay() {
        let evening = Schedule(medicationID: Fixed.medA, slot: .evening, dosePerIntake: 1)
        let result = rate(doses: [], schedules: [morning(), evening])
        // 아침 9/2~9/21 = 20, 저녁 9/1~9/21 = 21.
        XCTAssertEqual(result?.expected, 41)
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
    /// 9/1 10시 + 28일 = 9/29 10시. 9/29 8시 아침까지 28칸.
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
            doses: (2...15).map { taken(day: $0) } + after,
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
        // 9/1 진료(28일치)를 9/15 새벽에 앱을 깔고 적었다. 9/15~9/21 아침은
        // 꼬박 먹었다.
        var registered = medication()
        registered.createdAt = Fixed.date(2026, 9, 15, 7, 0)
        let result = rate(
            doses: (15...21).map { taken(day: $0) },
            medications: [registered]
        )
        // 분모는 등록 뒤 9/15~9/21 의 아침 7칸.
        XCTAssertEqual(result?.expected, 7, "등록 전 14일은 분모에 없다")
        XCTAssertEqual(result?.taken, 7)
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
        // 약 A 는 아침 3정(14일에 42정), 약 B 는 아침 1정(14정).
        let stock = [
            refill(42, medicationID: Fixed.medA),
            refill(14, medicationID: Fixed.medB)
        ]
        // 진료 뒤 14일(9/2~9/15 아침) 내내 A 만 먹었다.
        let doses = (2...15).map { taken(day: $0, quantity: 3, medicationID: Fixed.medA) }

        let result = InventoryCalculator.prescriptionAdherence(
            prescriptions: [twoMedPrescription()],
            schedules: [morning(Fixed.medA, dose: 3), morning(Fixed.medB)],
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
        // A 만 꼬박 먹었다(9/2~9/29 아침). B 는 한 번도 안 먹고 9/15 에 끊었다.
        let doses = (2...29).map { taken(day: $0, medicationID: Fixed.medA) }

        let result = InventoryCalculator.prescriptionAdherence(
            prescriptions: [prescription()],
            schedules: [morning(Fixed.medA), morning(Fixed.medB)],
            stockEvents: stock,
            doseEvents: doses,
            medications: [medication(), stopped],
            asOf: Fixed.date(2026, 9, 29, 23, 0),
            calendar: calendar
        )

        let b = result?.items.first { $0.medicationID == Fixed.medB }
        XCTAssertEqual(b?.rate, 0, "2주 내내 건너뛴 약은 0% 다")
        // 끊은 9/15 정오까지 9/2~9/15 아침 14칸.
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
            schedules: [morning(Fixed.medA), morning(Fixed.medB)],
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
    private let morning = [Schedule(medicationID: Fixed.medA, slot: .morning, dosePerIntake: 1)]

    private func taken(_ month: Int, _ day: Int) -> DoseEvent {
        let at = Fixed.date(2026, month, day, 8, 0)
        return DoseEvent(
            medicationID: Fixed.medA, scheduledAt: at, actualAt: at,
            status: .taken, quantity: 1, kind: .scheduled,
            slotKey: DoseSlot.morning.storageKey
        )
    }

    /// 진료실에서 오늘 10시 진료를 먼저 적고 리포트를 뽑는다. 오늘 진료는
    /// 아직 지난 시간대가 없으니 건너뛰고 지난 진료로 센다 - 그리고 그 진료의
    /// 창은 **오늘 진료 시각에서 닫힌다**. 오늘 아침 약은 이전 처방의 몫이다.
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
            schedules: morning,
            stockEvents: stock,
            doseEvents: (2...21).map { taken(9, $0) } + [taken(9, 22)],
            medications: [Medication(id: Fixed.medA, name: "A")],
            asOf: Fixed.date(2026, 9, 22, 23, 0),
            calendar: calendar
        )
        XCTAssertEqual(result?.visitDate, earlier.visitDate, "오늘 진료는 건너뛴다")
        XCTAssertEqual(result?.windowStart, Fixed.date(2026, 9, 1, 10))
        XCTAssertEqual(result?.windowEnd, Fixed.date(2026, 9, 22, 10), "오늘 진료 시각에서 닫힌다")
        XCTAssertEqual(result?.expected, 21, "9/2~9/22 아침 21칸")
        XCTAssertEqual(result?.taken, 21, "오늘 아침 한 알은 이전 처방의 몫으로 든다")
        XCTAssertEqual(result?.rate, 1)
    }

    /// 같은 상황에서 자기전 약도 있으면, 진료 뒤 22:30 이 지난 밤에는 오늘
    /// 진료가 스스로 선다 - 저녁 것부터 새 처방이다.
    func testVisitTodayStandsOnItsOwnOnceAnEveningSlotHasPassed() {
        let earlier = Prescription(visitDate: Fixed.date(2026, 9, 1, 10), daysSupplied: 28)
        let today = Prescription(visitDate: Fixed.date(2026, 9, 22, 10), daysSupplied: 28)
        let stock = [
            StockEvent.refill(medicationID: Fixed.medA, quantity: 28,
                              at: earlier.visitDate, prescriptionID: earlier.id),
            StockEvent.refill(medicationID: Fixed.medA, quantity: 28,
                              at: today.visitDate, prescriptionID: today.id)
        ]
        let bedtime = Schedule(medicationID: Fixed.medA, slot: .bedtime, dosePerIntake: 1)
        let result = InventoryCalculator.prescriptionAdherence(
            prescriptions: [earlier, today],
            schedules: morning + [bedtime],
            stockEvents: stock,
            doseEvents: [taken(9, 22)],
            medications: [Medication(id: Fixed.medA, name: "A")],
            asOf: Fixed.date(2026, 9, 22, 23, 0),
            calendar: calendar
        )
        XCTAssertEqual(result?.visitDate, today.visitDate, "저녁 것부터 새 처방이다")
        XCTAssertEqual(result?.expected, 1, "진료 뒤 자기전 한 칸")
        XCTAssertEqual(result?.taken, 0, "오늘 아침 것은 이전 처방의 몫이라 여기 안 든다")
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
            schedules: morning,
            stockEvents: stock,
            doseEvents: (2...29).map { taken(8, $0) },
            medications: [Medication(id: Fixed.medA, name: "A")],
            asOf: Fixed.date(2026, 9, 22, 23, 0),
            calendar: calendar
        )
        XCTAssertEqual(result?.visitDate, earlier.visitDate)
        XCTAssertEqual(result?.expected, 28)
        XCTAssertEqual(result?.taken, 28)
    }
}
