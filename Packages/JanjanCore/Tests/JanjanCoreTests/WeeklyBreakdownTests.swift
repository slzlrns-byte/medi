import XCTest
@testable import JanjanCore

/// 주차별 구역(Pro). 여기서 지키는 것은 숫자가 아니라 두 가지다.
///   · 무료 종이에는 아예 생기지 않는다 - 패턴 보기(Pro)의 뒷문이 되면 안 된다.
///   · 자해·자살 생각은 잘리지 않는다 - 그 한 줄을 보이려고 만드는 종이다.
final class WeeklyBreakdownTests: XCTestCase {

    /// 창이 7/21 – 8/17 의 28일이라 4주로 딱 나뉜다.
    private let end = Fixed.date(2026, 8, 17, 21, 0)

    private func content(
        checkIns: [CheckIn] = [],
        symptoms: [SymptomEntry] = [],
        weekly: Bool = true,
        lastVisit: Date? = nil
    ) -> ReportContent {
        ReportComposer.make(
            endingAt: end,
            medications: [Medication(id: Fixed.medA, name: "에스시탈로프람", strengthText: "10mg")],
            schedules: [Schedule(medicationID: Fixed.medA, slot: .bedtime, dosePerIntake: 1)],
            doseEvents: [],
            stockEvents: [],
            checkIns: checkIns,
            symptomEntries: symptoms,
            lastVisit: lastVisit,
            weeklyBreakdown: weekly,
            calendar: Fixed.calendar
        )
    }

    private func texts(_ content: ReportContent) -> [String] {
        content.lines.map(\.text)
    }

    private func symptom(_ id: String, _ day: Int, month: Int = 8) -> SymptomEntry {
        SymptomEntry(symptomID: id, severity: 5, startedAt: Fixed.date(2026, month, day, 14, 0))
    }

    // MARK: - 잠금

    func testFreePaperHasNoWeeklySection() {
        let report = content(
            checkIns: [CheckIn(date: Fixed.date(2026, 8, 3), mood: .init(-1))],
            symptoms: [symptom("low_mood", 3)],
            weekly: false
        )
        XCTAssertFalse(texts(report).contains("주차별"))
        // 잠겼다는 말조차 적지 않는다. 이 종이는 진료실에서 의사가 본다.
        XCTAssertFalse(texts(report).contains(where: { $0.contains("Pro") }))
    }

    func testProPaperHasEveryWeekOfTheWindow() {
        let report = content(symptoms: [symptom("low_mood", 3)])
        let lines = texts(report)
        XCTAssertTrue(lines.contains("주차별"))
        XCTAssertTrue(lines.contains("1주차 · 7월 21일–7월 27일"))
        XCTAssertTrue(lines.contains("2주차 · 7월 28일–8월 3일"))
        XCTAssertTrue(lines.contains("3주차 · 8월 4일–8월 10일"))
        XCTAssertTrue(lines.contains("4주차 · 8월 11일–8월 17일"))
    }

    /// 지난 진료가 일주일 전이면 주차별은 위의 기분 구역과 같은 말이 된다.
    func testOneWeekWindowGetsNoSection() {
        let report = content(
            checkIns: [CheckIn(date: Fixed.date(2026, 8, 13), mood: .init(0))],
            lastVisit: Fixed.date(2026, 8, 11, 10, 0)
        )
        XCTAssertFalse(texts(report).contains("주차별"))
    }

    /// 마지막 주가 짧으면 짧은 대로 적는다 - 사흘치를 한 주로 읽으면 안 된다.
    func testShortLastWeekShowsItsRealRange() {
        let report = content(
            symptoms: [symptom("low_mood", 5)],
            lastVisit: Fixed.date(2026, 8, 3, 10, 0)
        )
        let lines = texts(report)
        XCTAssertTrue(lines.contains("1주차 · 8월 3일–8월 9일"))
        XCTAssertTrue(lines.contains("2주차 · 8월 10일–8월 16일"))
        XCTAssertTrue(lines.contains("3주차 · 8월 17일–8월 17일"))
    }

    // MARK: - 세기

    func testSymptomsAreCountedInTheirOwnWeek() {
        let report = content(symptoms: [
            symptom("low_mood", 4), symptom("low_mood", 5), symptom("low_mood", 6),
            symptom("anxiety_restless", 4),
            symptom("low_mood", 12)
        ])
        let lines = texts(report)
        XCTAssertTrue(lines.contains("가라앉음·우울감 3회 · 불안·초조 1회"))
        XCTAssertTrue(lines.contains("가라앉음·우울감 1회"))
    }

    func testMoodUsesTheMostChosenValue() {
        let report = content(checkIns: [
            CheckIn(date: Fixed.date(2026, 8, 12), mood: .init(-2)),
            CheckIn(date: Fixed.date(2026, 8, 13), mood: .init(-2)),
            CheckIn(date: Fixed.date(2026, 8, 14), mood: .init(1))
        ])
        XCTAssertTrue(texts(report).contains("기분 힘듦 · 2일"))
    }

    /// 기록이 끊긴 주를 지우지 않는다. 그것도 진료실에서 읽을 것 중 하나다.
    func testEmptyWeekIsStillListed() {
        let report = content(symptoms: [symptom("low_mood", 12)])
        XCTAssertEqual(
            texts(report).filter { $0 == "이 주에는 기록이 없습니다." }.count,
            3
        )
    }

    func testNothingRecordedMeansNoSection() {
        XCTAssertFalse(texts(content()).contains("주차별"))
    }

    // MARK: - 안전

    /// 다섯 가지가 넘게 적힌 주에서 자해·자살 생각이 가장 적게 적혔어도 남는다.
    func testSafetySymptomSurvivesTheLimit() {
        let report = content(symptoms: [
            symptom("low_mood", 11), symptom("low_mood", 12), symptom("low_mood", 13),
            symptom("anxiety_restless", 11), symptom("anxiety_restless", 12),
            symptom("trouble_falling_asleep", 11), symptom("trouble_falling_asleep", 12),
            symptom("palpitations", 11), symptom("palpitations", 12),
            symptom("panic", 11),
            symptom("self_harm_thoughts", 13)
        ])
        let week = texts(report).first { $0.contains("자해·자살 생각") }
        XCTAssertNotNil(week, "자해·자살 생각이 횟수가 적다는 이유로 잘렸습니다")
        XCTAssertTrue(week?.contains("자해·자살 생각 1회") == true)
        // 잘림은 그대로 지켜진다 - 안전 항목만 덤으로 남는다.
        XCTAssertFalse(week?.contains("공황") == true)
    }
}
