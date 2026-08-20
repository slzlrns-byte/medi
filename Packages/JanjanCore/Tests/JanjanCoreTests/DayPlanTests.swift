import XCTest
@testable import JanjanCore

/// 하루 계획이 스케줄·복용 사건에서 어떻게 만들어지는지 한 줄씩 확인한다.
/// 오늘 화면과 워치가 같은 숫자를 말하는 근거가 이 파일이다.
final class DayPlanTests: XCTestCase {

    // 2026-08-17 은 월요일(Calendar.weekday == 2).
    private let monday = Fixed.date(2026, 8, 17, 9, 0)

    private var medications: [Medication] {
        [
            Medication(id: Fixed.medA, name: "에스시탈로프람", strengthText: "10mg"),
            Medication(id: Fixed.medB, name: "쿠에티아핀", strengthText: "25mg")
        ]
    }

    private var schedules: [Schedule] {
        [
            Schedule(medicationID: Fixed.medA, slot: .morning, dosePerIntake: 1),
            Schedule(medicationID: Fixed.medB, slot: .bedtime, dosePerIntake: Fixed.decimal("0.5"))
        ]
    }

    private func plan(
        schedules: [Schedule]? = nil,
        medications: [Medication]? = nil,
        doses: [DoseEvent] = []
    ) -> [DayPlan.SlotLine] {
        DayPlan.slots(
            on: monday,
            schedules: schedules ?? self.schedules,
            medications: medications ?? self.medications,
            doseEvents: doses,
            calendar: Fixed.calendar
        )
    }

    // MARK: - 묶기와 정렬

    func testGroupsSchedulesBySlotInTimeOrder() {
        let slots = plan()

        XCTAssertEqual(slots.count, 2)
        XCTAssertEqual(slots[0].slot, .morning)
        XCTAssertEqual(slots[1].slot, .bedtime)
        XCTAssertEqual(slots[0].time, TimeOfDay(hour: 8, minute: 0))
        XCTAssertEqual(slots[1].time, TimeOfDay(hour: 22, minute: 30))
    }

    func testSortsByMovedTimeNotByPresetOrder() {
        // 취침 약을 새벽 6시로 옮기면 아침보다 먼저 와야 한다.
        let moved = [
            Schedule(medicationID: Fixed.medA, slot: .morning, dosePerIntake: 1),
            Schedule(
                medicationID: Fixed.medB,
                slot: .bedtime,
                timeOfDay: TimeOfDay(hour: 6, minute: 0),
                dosePerIntake: 1
            )
        ]

        let slots = plan(schedules: moved)
        XCTAssertEqual(slots.map(\.slot), [.bedtime, .morning])
    }

    func testSameSlotTakesEarliestTime() {
        let two = [
            Schedule(
                medicationID: Fixed.medA,
                slot: .morning,
                timeOfDay: TimeOfDay(hour: 9, minute: 30),
                dosePerIntake: 1
            ),
            Schedule(
                medicationID: Fixed.medB,
                slot: .morning,
                timeOfDay: TimeOfDay(hour: 7, minute: 15),
                dosePerIntake: 1
            )
        ]

        let slots = plan(schedules: two)
        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots[0].time, TimeOfDay(hour: 7, minute: 15))
        XCTAssertEqual(slots[0].entries.count, 2)
    }

    // MARK: - 무엇이 빠지는가

    func testStoppedMedicationLeavesThePlan() {
        let stopped = [
            Medication(id: Fixed.medA, name: "에스시탈로프람", status: .stopped),
            Medication(id: Fixed.medB, name: "쿠에티아핀")
        ]

        let slots = plan(medications: stopped)
        XCTAssertEqual(slots.map(\.slot), [.bedtime])
    }

    func testScheduleWithoutMedicationIsDropped() {
        // 약을 지웠는데 스케줄이 남아 있어도 화면이 빈 줄을 그리지 않는다.
        let orphan = [Schedule(medicationID: UUID(), slot: .noon, dosePerIntake: 1)]
        XCTAssertTrue(plan(schedules: orphan).isEmpty)
    }

    func testWeekdayOffMeansNoLineThatDay() {
        // 월요일에만 먹는 약이므로 월요일에는 있고,
        let mondayOnly = [
            Schedule(
                medicationID: Fixed.medA,
                slot: .morning,
                weekdays: [.monday],
                dosePerIntake: 1
            )
        ]
        XCTAssertEqual(plan(schedules: mondayOnly).count, 1)

        // 화요일에는 없다.
        let tuesday = DayPlan.slots(
            on: Fixed.date(2026, 8, 18, 9, 0),
            schedules: mondayOnly,
            medications: medications,
            doseEvents: [],
            calendar: Fixed.calendar
        )
        XCTAssertTrue(tuesday.isEmpty)
    }

    func testEndedScheduleIsDropped() {
        let ended = [
            Schedule(
                medicationID: Fixed.medA,
                slot: .morning,
                dosePerIntake: 1,
                endDate: Fixed.date(2026, 8, 10, 9, 0)
            )
        ]
        XCTAssertTrue(plan(schedules: ended).isEmpty)
    }

    // MARK: - 기록 붙이기

    func testUnansweredSlotIsNotCompleted() {
        let slots = plan()
        XCTAssertFalse(slots[0].isCompleted)
        XCTAssertEqual(slots[0].pendingCount, 1)
        XCTAssertNil(slots[0].entries[0].status)
    }

    func testTakenMarksSlotCompleted() {
        let doses = [
            DoseEvent(
                medicationID: Fixed.medA,
                scheduledAt: Fixed.date(2026, 8, 17, 8, 0),
                actualAt: Fixed.date(2026, 8, 17, 8, 5),
                status: .taken,
                quantity: 1,
                kind: .scheduled,
                slotKey: DoseSlot.morning.storageKey
            )
        ]

        let slots = plan(doses: doses)
        XCTAssertTrue(slots[0].isCompleted)
        XCTAssertEqual(slots[0].entries[0].status, .taken)
        XCTAssertEqual(slots[0].pendingCount, 0)
    }

    func testSkippedAlsoCountsAsAnswered() {
        // 건너뜀은 정상적인 선택이다. 답을 준 것으로 세고 압박하지 않는다.
        let doses = [
            DoseEvent(
                medicationID: Fixed.medA,
                scheduledAt: Fixed.date(2026, 8, 17, 8, 0),
                status: .skipped,
                quantity: 1,
                kind: .scheduled,
                slotKey: DoseSlot.morning.storageKey
            )
        ]
        XCTAssertTrue(plan(doses: doses)[0].isCompleted)
    }

    func testUnrecordedIsNotAnAnswer() {
        // 알림에 응답하지 않아 미기록으로 남은 것은 "답함" 이 아니다.
        let doses = [
            DoseEvent(
                medicationID: Fixed.medA,
                scheduledAt: Fixed.date(2026, 8, 17, 8, 0),
                status: .unrecorded,
                quantity: 1,
                kind: .scheduled,
                slotKey: DoseSlot.morning.storageKey
            )
        ]

        let slots = plan(doses: doses)
        XCTAssertFalse(slots[0].isCompleted)
        XCTAssertEqual(slots[0].entries[0].status, .unrecorded)
    }

    func testLatestEventWins() {
        // 알림으로 건너뜀을 눌렀다가 앱에서 복용함으로 고친 경우.
        let doses = [
            DoseEvent(
                medicationID: Fixed.medA,
                scheduledAt: Fixed.date(2026, 8, 17, 8, 0),
                status: .skipped,
                quantity: 1,
                kind: .scheduled,
                slotKey: DoseSlot.morning.storageKey
            ),
            DoseEvent(
                medicationID: Fixed.medA,
                scheduledAt: Fixed.date(2026, 8, 17, 8, 0),
                actualAt: Fixed.date(2026, 8, 17, 10, 0),
                status: .taken,
                quantity: 1,
                kind: .scheduled,
                slotKey: DoseSlot.morning.storageKey
            )
        ]
        XCTAssertEqual(plan(doses: doses)[0].entries[0].status, .taken)
    }

    func testOtherDaysEventDoesNotLeakIn() {
        let yesterday = [
            DoseEvent(
                medicationID: Fixed.medA,
                scheduledAt: Fixed.date(2026, 8, 16, 8, 0),
                actualAt: Fixed.date(2026, 8, 16, 8, 0),
                status: .taken,
                quantity: 1,
                kind: .scheduled,
                slotKey: DoseSlot.morning.storageKey
            )
        ]
        XCTAssertNil(plan(doses: yesterday)[0].entries[0].status)
    }

    func testAsNeededEventIsIgnored() {
        // 필요시 복용은 시간대 계획에 끼어들지 않는다.
        let prn = [
            DoseEvent(
                medicationID: Fixed.medA,
                scheduledAt: Fixed.date(2026, 8, 17, 8, 0),
                actualAt: Fixed.date(2026, 8, 17, 8, 0),
                status: .taken,
                quantity: 1,
                kind: .asNeeded,
                slotKey: DoseSlot.morning.storageKey
            )
        ]
        XCTAssertNil(plan(doses: prn)[0].entries[0].status)
    }

    func testOtherSlotEventDoesNotLeakIn() {
        let bedtime = [
            DoseEvent(
                medicationID: Fixed.medA,
                scheduledAt: Fixed.date(2026, 8, 17, 22, 30),
                actualAt: Fixed.date(2026, 8, 17, 22, 30),
                status: .taken,
                quantity: 1,
                kind: .scheduled,
                slotKey: DoseSlot.bedtime.storageKey
            )
        ]
        XCTAssertNil(plan(doses: bedtime)[0].entries[0].status)
    }

    func testLateNightDoseStaysOnItsScheduledDay() {
        // 어젯밤 22:30 취침약을 자정 넘겨 00:10 에 먹은 경우.
        // 실제 복용 시각은 다음 날이지만 그 줄은 여전히 어제의 취침 줄이다.
        let doses = [
            DoseEvent(
                medicationID: Fixed.medB,
                scheduledAt: Fixed.date(2026, 8, 17, 22, 30),
                actualAt: Fixed.date(2026, 8, 18, 0, 10),
                status: .taken,
                quantity: Fixed.decimal("0.5"),
                kind: .scheduled,
                slotKey: DoseSlot.bedtime.storageKey
            )
        ]

        let today = plan(doses: doses)
        XCTAssertEqual(today[1].entries[0].status, .taken)
        XCTAssertTrue(today[1].isCompleted)

        // 다음 날 취침 줄은 아직 비어 있어야 한다.
        let tomorrow = DayPlan.slots(
            on: Fixed.date(2026, 8, 18, 9, 0),
            schedules: schedules,
            medications: medications,
            doseEvents: doses,
            calendar: Fixed.calendar
        )
        XCTAssertNil(tomorrow[1].entries[0].status)
    }

    // MARK: - 요약

    func testPendingCounts() {
        let doses = [
            DoseEvent(
                medicationID: Fixed.medA,
                scheduledAt: Fixed.date(2026, 8, 17, 8, 0),
                actualAt: Fixed.date(2026, 8, 17, 8, 0),
                status: .taken,
                quantity: 1,
                kind: .scheduled,
                slotKey: DoseSlot.morning.storageKey
            )
        ]

        let slots = plan(doses: doses)
        XCTAssertEqual(DayPlan.pendingCount(in: slots), 1)
        XCTAssertEqual(DayPlan.pendingSlotCount(in: slots), 1)
    }

    func testNextPendingSlotPrefersTheOneAhead() {
        let slots = plan()
        let next = DayPlan.nextPendingSlot(
            in: slots,
            at: Fixed.date(2026, 8, 17, 12, 0),
            calendar: Fixed.calendar
        )
        XCTAssertEqual(next?.slot, .bedtime)
    }

    func testNextPendingSlotFallsBackToThePastWhenAllTimesPassed() {
        // 자정 직전이면 앞으로 남은 시간대가 없다. 그래도 놓친 것을 가리켜야 한다.
        let slots = plan()
        let next = DayPlan.nextPendingSlot(
            in: slots,
            at: Fixed.date(2026, 8, 17, 23, 50),
            calendar: Fixed.calendar
        )
        XCTAssertEqual(next?.slot, .morning)
    }

    func testNextPendingSlotIsNilWhenEverythingAnswered() {
        let doses = [
            DoseEvent(
                medicationID: Fixed.medA,
                scheduledAt: Fixed.date(2026, 8, 17, 8, 0),
                actualAt: Fixed.date(2026, 8, 17, 8, 0),
                status: .taken,
                quantity: 1,
                kind: .scheduled,
                slotKey: DoseSlot.morning.storageKey
            ),
            DoseEvent(
                medicationID: Fixed.medB,
                scheduledAt: Fixed.date(2026, 8, 17, 22, 30),
                status: .skipped,
                quantity: Fixed.decimal("0.5"),
                kind: .scheduled,
                slotKey: DoseSlot.bedtime.storageKey
            )
        ]

        let slots = plan(doses: doses)
        XCTAssertEqual(DayPlan.pendingCount(in: slots), 0)
        XCTAssertNil(
            DayPlan.nextPendingSlot(in: slots, at: monday, calendar: Fixed.calendar)
        )
    }

    // MARK: - 알림 목록

    func testWeeklyRemindersCoverEveryWeekday() {
        let reminders = DayPlan.weeklyReminders(
            schedules: schedules,
            medications: medications,
            asOf: monday
        )
        // 시간대 2개 × 요일 7일.
        XCTAssertEqual(reminders.count, 14)
    }

    func testWeekdayOnlyMedicationDoesNotAppearOnOtherDays() {
        // 월요일만 먹는 약과 매일 먹는 약이 같은 아침 시간대에 있을 때,
        // 화요일 알림 문구에 월요일 약 이름이 끼면 안 된다.
        let mixed = [
            Schedule(medicationID: Fixed.medA, slot: .morning, dosePerIntake: 1),
            Schedule(
                medicationID: Fixed.medB,
                slot: .morning,
                weekdays: [.monday],
                dosePerIntake: 1
            )
        ]

        let reminders = DayPlan.weeklyReminders(
            schedules: mixed,
            medications: medications,
            asOf: monday
        )

        let mondayMorning = reminders.first { $0.weekday == .monday && $0.slot == .morning }
        XCTAssertEqual(mondayMorning?.medicationIDs.count, 2)

        let tuesdayMorning = reminders.first { $0.weekday == .tuesday && $0.slot == .morning }
        XCTAssertEqual(tuesdayMorning?.medicationIDs, [Fixed.medA])
        XCTAssertEqual(tuesdayMorning?.medicationNames, ["에스시탈로프람"])
    }

    func testEndedScheduleMakesNoReminder() {
        let ended = [
            Schedule(
                medicationID: Fixed.medA,
                slot: .morning,
                dosePerIntake: 1,
                endDate: Fixed.date(2026, 8, 10, 9, 0)
            )
        ]
        XCTAssertTrue(
            DayPlan.weeklyReminders(schedules: ended, medications: medications, asOf: monday).isEmpty
        )
    }

    func testStoppedMedicationMakesNoReminder() {
        let stopped = [Medication(id: Fixed.medA, name: "에스시탈로프람", status: .stopped)]
        let onlyA = [Schedule(medicationID: Fixed.medA, slot: .morning, dosePerIntake: 1)]
        XCTAssertTrue(
            DayPlan.weeklyReminders(schedules: onlyA, medications: stopped, asOf: monday).isEmpty
        )
    }

    func testReminderIdentifiersAreUnique() {
        // 알림 식별자가 겹치면 나중 것이 앞의 것을 조용히 덮어써 알림이 사라진다.
        let reminders = DayPlan.weeklyReminders(
            schedules: schedules,
            medications: medications,
            asOf: monday
        )
        XCTAssertEqual(Set(reminders.map(\.id)).count, reminders.count)
    }

    func testReminderTakesEarliestTimeInSlot() {
        let two = [
            Schedule(
                medicationID: Fixed.medA,
                slot: .morning,
                timeOfDay: TimeOfDay(hour: 9, minute: 30),
                dosePerIntake: 1
            ),
            Schedule(
                medicationID: Fixed.medB,
                slot: .morning,
                timeOfDay: TimeOfDay(hour: 7, minute: 15),
                dosePerIntake: 1
            )
        ]

        let reminders = DayPlan.weeklyReminders(
            schedules: two,
            medications: medications,
            asOf: monday
        )
        XCTAssertEqual(reminders.first?.time, TimeOfDay(hour: 7, minute: 15))
    }

    // MARK: - 워치 스냅샷

    func testWatchSnapshotMirrorsThePlan() {
        let snapshot = DayPlan.watchSnapshot(
            on: monday,
            schedules: schedules,
            medications: medications,
            doseEvents: [],
            calendar: Fixed.calendar,
            generatedAt: monday
        )

        XCTAssertEqual(snapshot.slots.count, 2)
        XCTAssertEqual(snapshot.slots[0].slotKey, DoseSlot.morning.storageKey)
        XCTAssertEqual(snapshot.slots[0].labelKo, "아침")
        XCTAssertEqual(snapshot.slots[0].timeText, "08:00")
        XCTAssertEqual(snapshot.slots[0].medicationNames, ["에스시탈로프람"])
        XCTAssertFalse(snapshot.slots[0].isCompleted)
        XCTAssertEqual(snapshot.remainingCountToday, 2)
    }

    func testWatchSnapshotIsCodable() {
        // WatchConnectivity 로 건너가는 값이라 굽고 되살리는 길이 막히면 워치가 빈 화면이 된다.
        let snapshot = DayPlan.watchSnapshot(
            on: monday,
            schedules: schedules,
            medications: medications,
            doseEvents: [],
            calendar: Fixed.calendar,
            generatedAt: monday
        )

        let data = try? JSONEncoder().encode(snapshot)
        XCTAssertNotNil(data)
        let restored = data.flatMap { try? JSONDecoder().decode(WatchSnapshot.self, from: $0) }
        XCTAssertEqual(restored, snapshot)
    }
}
