import XCTest
@testable import JanjanCore

/// "패턴 보기" 계산. 세 줄(기분·복약·수면)이 같은 날짜 열에 놓이는지를 잠근다.
/// 해석(상관·추세)은 만들지 않는다는 원칙은 API 모양 자체로 지켜진다 —
/// 여기에는 날짜별 원자료만 있다.
final class PatternTimelineTests: XCTestCase {

    private let medications = [
        Medication(id: Fixed.medA, name: "에스시탈로프람", strengthText: "10mg")
    ]
    private let schedules = [
        Schedule(medicationID: Fixed.medA, slot: .morning, dosePerIntake: 1)
    ]

    func testDaysRunOldestToNewestAndCount() {
        let timeline = PatternTimeline.make(
            dayCount: 7,
            endingAt: Fixed.date(2026, 9, 10, 15, 0),
            checkIns: [],
            schedules: [],
            medications: [],
            doseEvents: [],
            calendar: Fixed.calendar
        )
        XCTAssertEqual(timeline.days.count, 7)
        XCTAssertEqual(timeline.days.first?.date, Fixed.calendar.startOfDay(for: Fixed.date(2026, 9, 4)))
        XCTAssertEqual(timeline.days.last?.date, Fixed.calendar.startOfDay(for: Fixed.date(2026, 9, 10)))
    }

    func testMoodAndSleepLandOnTheirOwnDay() {
        let checkIn = CheckIn(
            date: Fixed.date(2026, 9, 9, 21, 0),
            mood: .init(2),
            sleepMinutes: 7 * 60,
            updatedAt: Fixed.date(2026, 9, 9, 21, 0)
        )
        let timeline = PatternTimeline.make(
            dayCount: 3,
            endingAt: Fixed.date(2026, 9, 10),
            checkIns: [checkIn],
            schedules: [],
            medications: [],
            doseEvents: [],
            calendar: Fixed.calendar
        )
        XCTAssertEqual(timeline.days[1].moodScore, 2)
        XCTAssertEqual(timeline.days[1].sleepMinutes, 7 * 60)
        XCTAssertNil(timeline.days[0].moodScore)
        XCTAssertNil(timeline.days[2].moodScore)
    }

    /// 답하지 않은 시간대는 기록에 줄이 없다. 계획에서 세어야
    /// "안 답한 날" 과 "계획이 없던 날" 이 구별된다.
    func testDoseCountsComeFromThePlanNotOnlyFromEvents() {
        let taken = DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 9, 9, 8, 0),
            actualAt: Fixed.date(2026, 9, 9, 8, 5),
            status: .taken,
            quantity: 1,
            kind: .scheduled,
            slotKey: DoseSlot.morning.storageKey
        )
        let timeline = PatternTimeline.make(
            dayCount: 2,
            endingAt: Fixed.date(2026, 9, 10),
            checkIns: [],
            schedules: schedules,
            medications: medications,
            doseEvents: [taken],
            calendar: Fixed.calendar
        )
        // 9월 9일: 예정 1 · 복용 1 → 전부.
        XCTAssertEqual(timeline.days[0].scheduledCount, 1)
        XCTAssertEqual(timeline.days[0].takenCount, 1)
        XCTAssertEqual(timeline.days[0].takenFraction, 1.0)
        // 9월 10일: 예정 1 · 답 없음 → 0. 계획이 없던 날(nil)과 다르다.
        XCTAssertEqual(timeline.days[1].scheduledCount, 1)
        XCTAssertEqual(timeline.days[1].takenCount, 0)
        XCTAssertEqual(timeline.days[1].takenFraction, 0.0)
    }

    func testNoScheduleMeansNoFractionNotZero() {
        let timeline = PatternTimeline.make(
            dayCount: 1,
            endingAt: Fixed.date(2026, 9, 10),
            checkIns: [],
            schedules: [],
            medications: medications,
            doseEvents: [],
            calendar: Fixed.calendar
        )
        XCTAssertEqual(timeline.days[0].scheduledCount, 0)
        XCTAssertNil(timeline.days[0].takenFraction, "계획이 없던 날은 0% 가 아니라 빈 칸입니다")
    }
}

// MARK: - 중단한 약 (QA 2026-09-21)

extension PatternTimelineTests {

    /// 약 하나를 끊는 순간 지난 4주가 다시 그려지면 안 된다.
    ///
    /// 아침 약은 다 먹고 저녁 약은 2주 내내 건너뛴 사람. 저녁 약을 끊으면
    /// `DayPlan` 이 지금 상태만 보므로 지난 2주에서 저녁 줄이 통째로 사라져
    /// 그래프가 갑자기 꽉 찬다. 같은 날 뽑은 종이는 여전히 절반이다.
    func testStoppingAMedicationDoesNotRefillThePastChart() {
        let end = Fixed.date(2026, 9, 14, 23)
        let stoppedAt = Fixed.date(2026, 9, 14, 12)

        let morning = Medication(id: Fixed.medA, name: "아침약")
        var evening = Medication(id: Fixed.medB, name: "저녁약")
        evening.status = .stopped
        evening.stoppedAt = stoppedAt

        let schedules = [
            Schedule(medicationID: Fixed.medA, slot: .morning, dosePerIntake: 1),
            Schedule(medicationID: Fixed.medB, slot: .evening, dosePerIntake: 1)
        ]

        var doses: [DoseEvent] = []
        for day in 1...13 {
            doses.append(DoseEvent(
                medicationID: Fixed.medA,
                scheduledAt: Fixed.date(2026, 9, day, 8),
                actualAt: Fixed.date(2026, 9, day, 8),
                status: .taken, quantity: 1, kind: .scheduled,
                slotKey: DoseSlot.morning.storageKey
            ))
            doses.append(DoseEvent(
                medicationID: Fixed.medB,
                scheduledAt: Fixed.date(2026, 9, day, 19),
                status: .skipped, quantity: 1, kind: .scheduled,
                slotKey: DoseSlot.evening.storageKey
            ))
        }

        let timeline = PatternTimeline.make(
            dayCount: 14,
            endingAt: end,
            checkIns: [],
            schedules: schedules,
            medications: [morning, evening],
            doseEvents: doses,
            calendar: Fixed.calendar
        )

        // 중단 전의 날에는 두 줄이 다 서 있어야 한다.
        let before = timeline.days.first { Fixed.calendar.isDate($0.date, inSameDayAs: Fixed.date(2026, 9, 5)) }
        XCTAssertEqual(before?.scheduledCount, 2, "끊기 전 날에는 저녁 약도 예정에 있었다")
        XCTAssertEqual(before?.takenCount, 1, "저녁 약은 건너뛰었다")

        // 중단한 뒤의 날에는 아침 약만 남는다.
        let after = timeline.days.last
        XCTAssertEqual(after?.scheduledCount, 1, "끊은 뒤에는 저녁 약이 빠진다")
    }
}
