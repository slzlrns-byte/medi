import XCTest
@testable import JanjanCore

/// 진료 알림.
///
/// 복약 알림보다 드물지만 놓쳤을 때의 무게는 더 크다 — 진료를 놓치면 약이 끊긴다.
/// 그래서 **지난 시각으로 예약하지 않는 것**이 이 파일에서 가장 중요하다.
/// 지난 시각으로 걸면 iOS 가 그 자리에서 울려 "내일 진료예요" 가 진료 다음 날 뜬다.
final class AppointmentReminderTests: XCTestCase {

    /// 2026-08-20 목요일 오전 9시.
    private let now = Fixed.date(2026, 8, 20, 9, 0)

    private func make(
        _ visits: [Date],
        leadDays: Int = AppointmentReminder.defaultLeadDays
    ) -> [AppointmentReminder.Reminder] {
        AppointmentReminder.reminders(
            visitDates: visits,
            leadDays: leadDays,
            now: now,
            calendar: Fixed.calendar
        )
    }

    // MARK: - 언제 뜨는가

    func testFiresTheEveningBefore() {
        let visit = Fixed.date(2026, 8, 30, 10, 0)
        let reminders = make([visit])

        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders[0].fireAt, Fixed.date(2026, 8, 29, 19, 0))
        XCTAssertEqual(reminders[0].bodyKo, "내일이에요.")
    }

    func testSameDayFiresInTheMorningNotTheEvening() {
        // 저녁 7시에 "오늘이에요" 는 이미 늦다.
        let reminders = make([Fixed.date(2026, 8, 30, 10, 0)], leadDays: 0)
        XCTAssertEqual(reminders[0].fireAt, Fixed.date(2026, 8, 30, 8, 0))
        XCTAssertEqual(reminders[0].bodyKo, "오늘이에요.")
    }

    func testWeekAheadKeepsTheEveningTime() {
        let reminders = make([Fixed.date(2026, 8, 30, 10, 0)], leadDays: 7)
        XCTAssertEqual(reminders[0].fireAt, Fixed.date(2026, 8, 23, 19, 0))
        XCTAssertEqual(reminders[0].bodyKo, "7일 뒤예요.")
    }

    // MARK: - 무엇을 걸지 않는가

    func testPastVisitsAreIgnored() {
        XCTAssertTrue(make([Fixed.date(2026, 8, 10, 10, 0)]).isEmpty)
    }

    func testTodaysVisitIsStillAVisit() {
        // 오늘 진료인데 당일 알림 시각(08:00)이 이미 지났다면 걸지 않는다.
        XCTAssertTrue(make([Fixed.date(2026, 8, 20, 15, 0)], leadDays: 0).isEmpty)
    }

    func testDoesNotScheduleInThePast() {
        // 내일 진료인데 어제 저녁에 알렸어야 하는 경우.
        XCTAssertTrue(make([Fixed.date(2026, 8, 21, 10, 0)], leadDays: 2).isEmpty)
    }

    func testOffMeansNothing() {
        let visit = Fixed.date(2026, 8, 30, 10, 0)
        XCTAssertTrue(make([visit], leadDays: AppointmentReminder.off).isEmpty)
        XCTAssertTrue(make([visit], leadDays: -5).isEmpty)
    }

    func testSameDayIsOnlyRemindedOnce() {
        // 같은 날짜가 여러 처방에 적혀 있어도 알림은 하나다.
        let visit = Fixed.date(2026, 8, 30, 10, 0)
        let another = Fixed.date(2026, 8, 30, 15, 0)
        XCTAssertEqual(make([visit, another]).count, 1)
    }

    func testSeveralVisitsComeInOrder() {
        let reminders = make([
            Fixed.date(2026, 9, 20, 10, 0),
            Fixed.date(2026, 8, 30, 10, 0)
        ])
        XCTAssertEqual(reminders.count, 2)
        XCTAssertLessThan(reminders[0].fireAt, reminders[1].fireAt)
    }

    // MARK: - 식별자

    func testIdentifierIsOnePerDay() {
        let morning = AppointmentReminder.identifier(
            for: Fixed.date(2026, 8, 30, 9, 0), calendar: Fixed.calendar
        )
        let evening = AppointmentReminder.identifier(
            for: Fixed.date(2026, 8, 30, 21, 0), calendar: Fixed.calendar
        )
        XCTAssertEqual(morning, evening)
        XCTAssertEqual(morning, "visit-20260830")
    }

    func testIdentifiersAreUniquePerVisit() {
        let reminders = make([
            Fixed.date(2026, 8, 30, 10, 0),
            Fixed.date(2026, 9, 20, 10, 0)
        ])
        XCTAssertEqual(Set(reminders.map(\.id)).count, reminders.count)
    }

    /// 복약 알림과 식별자가 겹치면 서로를 지운다.
    func testIdentifierDoesNotCollideWithDoseReminders() {
        let id = AppointmentReminder.identifier(for: now, calendar: Fixed.calendar)
        XCTAssertTrue(id.hasPrefix("visit-"))
        XCTAssertFalse(id.hasPrefix("dose-"))
    }

    // MARK: - 문구

    func testBodyReadsNaturally() {
        XCTAssertEqual(AppointmentReminder.bodyKo(daysUntilVisit: 0), "오늘이에요.")
        XCTAssertEqual(AppointmentReminder.bodyKo(daysUntilVisit: 1), "내일이에요.")
        XCTAssertEqual(AppointmentReminder.bodyKo(daysUntilVisit: 2), "모레예요.")
        XCTAssertEqual(AppointmentReminder.bodyKo(daysUntilVisit: 5), "5일 뒤예요.")
    }

    func testNothingNagsOrShouts() {
        var texts = AppointmentReminder.allowedLeadDays.map(AppointmentReminder.leadLabelKo(forDays:))
        texts += (0...9).map(AppointmentReminder.bodyKo(daysUntilVisit:))
        texts.append(make([Fixed.date(2026, 8, 30, 10, 0)])[0].titleKo)

        for text in texts {
            XCTAssertFalse(text.contains("!"))
            for word in ["잊지", "꼭", "반드시", "놓치", "경고", "빨리"] {
                XCTAssertFalse(text.contains(word), "재촉하는 말이 들어갔습니다: \(text)")
            }
        }
    }

    func testLeadLabels() {
        XCTAssertEqual(AppointmentReminder.leadLabelKo(forDays: AppointmentReminder.off), "안 함")
        XCTAssertEqual(AppointmentReminder.leadLabelKo(forDays: 0), "당일 아침")
        XCTAssertEqual(AppointmentReminder.leadLabelKo(forDays: 1), "하루 전 저녁")
    }
}
