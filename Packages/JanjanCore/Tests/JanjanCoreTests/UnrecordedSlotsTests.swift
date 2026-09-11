import XCTest
@testable import JanjanCore

/// "기록 없이 지나간 시간대" 를 찾는 규칙. 핵심은 셋이다:
/// 아직 안 온 시간대는 빠트린 것이 아니고, 이미 답한 줄(미기록 포함)은 다시 묻지 않고,
/// 어느 날을 빠트렸는지 앱이 짐작하지 않는다(그래서 날짜·시간대 이름으로 하나씩 든다).
final class UnrecordedSlotsTests: XCTestCase {

    // 2026-08-17 은 월요일. now 는 화요일 정오.
    private let monday = Fixed.date(2026, 8, 17, 0, 0)
    private let tuesdayNoon = Fixed.date(2026, 8, 18, 12, 0)

    private var medications: [Medication] {
        [
            Medication(id: Fixed.medA, name: "에스시탈로프람", strengthText: "10mg"),
            Medication(id: Fixed.medB, name: "쿠에티아핀", strengthText: "25mg")
        ]
    }

    private var schedules: [Schedule] {
        [
            Schedule(medicationID: Fixed.medA, slot: .morning, dosePerIntake: 1),
            Schedule(medicationID: Fixed.medB, slot: .bedtime, dosePerIntake: 1)
        ]
    }

    private func find(doses: [DoseEvent] = [], until now: Date? = nil) -> [UnrecordedSlots.Line] {
        UnrecordedSlots.find(
            from: monday,
            until: now ?? tuesdayNoon,
            schedules: schedules,
            medications: medications,
            doseEvents: doses,
            calendar: Fixed.calendar
        )
    }

    private func scheduledDose(
        _ medicationID: UUID, slot: DoseSlot, day: Date, status: DoseEvent.Status
    ) -> DoseEvent {
        let at = slot.defaultTime.date(on: day, calendar: Fixed.calendar)
        return DoseEvent(
            medicationID: medicationID,
            scheduledAt: at,
            actualAt: status == .taken ? at : nil,
            status: status,
            quantity: 1,
            kind: .scheduled,
            slotKey: slot.storageKey
        )
    }

    func testPassedSlotsWithoutRecordsAreListedInTimeOrder() {
        // 기록이 하나도 없다. 지난 것은 월요일 아침·취침과 화요일 아침 — 화요일 취침은 아직이다.
        let lines = find()
        XCTAssertEqual(lines.map(\.slot), [.morning, .bedtime, .morning])
        XCTAssertEqual(
            lines.map { Fixed.calendar.component(.day, from: $0.day) },
            [17, 17, 18]
        )
    }

    func testFutureSlotTodayIsNotMissed() {
        // 화요일 아침 9시: 화요일 취침은 물론, 아직 안 온 시간대는 어디에도 없다.
        let lines = find(until: Fixed.date(2026, 8, 18, 9, 0))
        XCTAssertFalse(lines.contains { line in
            line.slot == .bedtime && Fixed.calendar.component(.day, from: line.day) == 18
        })
    }

    func testAnsweredSlotsStayQuietIncludingExplicitUnrecorded() {
        // 월요일 아침은 복용함, 월요일 취침은 "기억 안 나요"(명시적 미기록).
        // 둘 다 답한 것이므로 남는 것은 화요일 아침 하나다.
        let doses = [
            scheduledDose(Fixed.medA, slot: .morning, day: monday, status: .taken),
            scheduledDose(Fixed.medB, slot: .bedtime, day: monday, status: .unrecorded)
        ]
        let lines = find(doses: doses)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.slot, .morning)
        XCTAssertEqual(lines.first.map { Fixed.calendar.component(.day, from: $0.day) }, Optional(18))
    }

    func testPartiallyRecordedSlotListsOnlyTheSilentMedication() {
        // 아침에 두 약이 있는데 하나만 기록했다 - 남은 약만 든다.
        let both = schedules + [Schedule(medicationID: Fixed.medB, slot: .morning, dosePerIntake: 1)]
        let doses = [scheduledDose(Fixed.medA, slot: .morning, day: monday, status: .taken)]
        let lines = UnrecordedSlots.find(
            from: monday,
            until: Fixed.date(2026, 8, 17, 12, 0),
            schedules: both,
            medications: medications,
            doseEvents: doses,
            calendar: Fixed.calendar
        )
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.entries.map(\.medicationID), [Fixed.medB])
    }

    func testLookbackIsBounded() {
        // 두 달 전부터 찾아 달라고 해도 최근 31일만 본다. 이 도구는 감사가 아니다.
        let start = Fixed.date(2026, 6, 1, 0, 0)
        let lines = UnrecordedSlots.find(
            from: start,
            until: tuesdayNoon,
            schedules: [Schedule(medicationID: Fixed.medA, slot: .morning, dosePerIntake: 1)],
            medications: medications,
            doseEvents: [],
            calendar: Fixed.calendar
        )
        XCTAssertEqual(lines.count, UnrecordedSlots.maxLookbackDays)
        let oldest = lines.first.map { Fixed.calendar.startOfDay(for: $0.day) }
        XCTAssertEqual(oldest, Fixed.calendar.date(byAdding: .day, value: -30, to: Fixed.calendar.startOfDay(for: tuesdayNoon)))
    }

    func testTitleSpeaksBothLanguages() {
        let line = UnrecordedSlots.Line(
            day: monday,
            slot: .morning,
            plannedAt: DoseSlot.morning.defaultTime.date(on: monday, calendar: Fixed.calendar),
            entries: []
        )
        XCTAssertEqual(UnrecordedSlots.title(for: line, language: .korean, calendar: Fixed.calendar), "8월 17일 월요일 · 아침")
        XCTAssertEqual(UnrecordedSlots.title(for: line, language: .english, calendar: Fixed.calendar), "Mon, Aug 17 · Morning")
    }

    func testStoppedMedicationKeepsItsPreStopGapsOnly() {
        // 월요일 아침을 비운 채, 화요일 오전 10시에 에스시탈로프람을 중단했다.
        // 중단 전(월 아침·화 아침 8시)은 여전히 들고, 중단 뒤는 빠트림이 아니다.
        let stoppedAt = Fixed.date(2026, 8, 18, 10, 0)
        let stopped = Medication(
            id: Fixed.medA, name: "에스시탈로프람", strengthText: "10mg",
            status: .stopped, stoppedAt: stoppedAt
        )
        let lines = UnrecordedSlots.find(
            from: monday,
            until: Fixed.date(2026, 8, 19, 12, 0),  // 수요일 정오
            schedules: [Schedule(medicationID: Fixed.medA, slot: .morning, dosePerIntake: 1)],
            medications: [stopped],
            doseEvents: [],
            calendar: Fixed.calendar
        )
        XCTAssertEqual(
            lines.map { Fixed.calendar.component(.day, from: $0.day) },
            [17, 18],
            "중단 전의 빈 아침 둘만 남아야 합니다 - 수요일은 빠트림이 아닙니다"
        )
    }

    func testStoppedWithoutTimestampStaysQuiet() {
        // 이 필드가 없던 판에서 중단한 약: 언제 중단했는지 모르므로 아예 들지 않는다.
        let stopped = Medication(
            id: Fixed.medA, name: "에스시탈로프람", strengthText: "10mg", status: .stopped
        )
        let lines = UnrecordedSlots.find(
            from: monday, until: tuesdayNoon,
            schedules: [Schedule(medicationID: Fixed.medA, slot: .morning, dosePerIntake: 1)],
            medications: [stopped], doseEvents: [], calendar: Fixed.calendar
        )
        XCTAssertTrue(lines.isEmpty)
    }

    func testEndedScheduleStopsProducingGaps() {
        // 월요일까지인 스케줄: 화요일 아침은 예정이 아니었으므로 빠트림도 아니다.
        let ended = Schedule(
            medicationID: Fixed.medA, slot: .morning, dosePerIntake: 1,
            endDate: monday
        )
        let lines = UnrecordedSlots.find(
            from: monday, until: tuesdayNoon,
            schedules: [ended], medications: medications, doseEvents: [],
            calendar: Fixed.calendar
        )
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first.map { Fixed.calendar.component(.day, from: $0.day) }, Optional(17))
    }
}
