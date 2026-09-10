import XCTest
@testable import JanjanCore

/// 진료에 가져갈 4주 요약이 무엇을 말하고 무엇을 말하지 않는지 확인한다.
/// 이 파일의 핵심은 숫자가 아니라 **판단하지 않는다**는 규칙이다.
final class ReportComposerTests: XCTestCase {

    private let end = Fixed.date(2026, 8, 17, 21, 0)

    private var medications: [Medication] {
        [
            Medication(id: Fixed.medA, name: "에스시탈로프람", strengthText: "10mg"),
            Medication(id: Fixed.medB, name: "쿠에티아핀", strengthText: "25mg", kind: .asNeeded)
        ]
    }

    private var schedules: [Schedule] {
        [Schedule(medicationID: Fixed.medA, slot: .bedtime, dosePerIntake: 1)]
    }

    private func content(
        medications: [Medication]? = nil,
        schedules: [Schedule]? = nil,
        doses: [DoseEvent] = [],
        stock: [StockEvent] = [],
        checkIns: [CheckIn] = [],
        doseChanges: [DoseChange] = [],
        lastVisit: Date? = nil,
        nextVisit: Date? = nil,
        questions: String = ""
    ) -> ReportContent {
        ReportComposer.make(
            endingAt: end,
            medications: medications ?? self.medications,
            schedules: schedules ?? self.schedules,
            doseEvents: doses,
            stockEvents: stock,
            checkIns: checkIns,
            doseChanges: doseChanges,
            lastVisit: lastVisit,
            nextVisit: nextVisit,
            questionsKo: questions,
            calendar: Fixed.calendar
        )
    }

    private func texts(_ content: ReportContent) -> [String] {
        content.lines.map(\.text)
    }

    // MARK: - 틀

    func testHeaderAndDisclaimer() {
        let report = content()
        XCTAssertEqual(report.titleKo, "더잔잔 · 4주 요약")
        XCTAssertEqual(report.disclaimerKo, Janjan.medicalDisclaimerKo)
        // 28일 창이므로 7/21 부터 8/17 까지.
        XCTAssertEqual(report.periodKo, "2026년 7월 21일 – 2026년 8월 17일")
    }

    func testSectionsAreInOrder() {
        let report = content(
            checkIns: [
                CheckIn(
                    date: Fixed.date(2026, 8, 16),
                    mood: .init(0),
                    dreamed: true,
                    dreamVividness: 3
                )
            ],
            doseChanges: [
                DoseChange(
                    medicationID: Fixed.medA,
                    changedAt: Fixed.date(2026, 8, 10),
                    fromText: "5mg",
                    toText: "10mg"
                )
            ]
        )
        let headings = report.lines.filter { $0.style == .heading }.map(\.text)
        XCTAssertEqual(headings, ["복약", "약", "용량 변경", "기분", "꿈"])
    }

    // MARK: - 진료 앵커

    func testWindowAnchorsToLastVisit() {
        // 8/5 에 진료를 다녀왔으면 8/5 부터 본다. 의사가 궁금한 것은 그 뒤의 일이다.
        let report = content(lastVisit: Fixed.date(2026, 8, 5, 10, 0))
        XCTAssertEqual(report.titleKo, "더잔잔 · 지난 진료 이후")
        XCTAssertEqual(report.periodKo, "2026년 8월 5일 – 2026년 8월 17일")
    }

    func testAnchoredWindowCountsItsOwnLength() {
        // 8/5~8/17 은 13일. "28일 중" 이라고 적으면 거짓말이 된다.
        let report = content(
            checkIns: [CheckIn(date: Fixed.date(2026, 8, 16), mood: .init(0))],
            lastVisit: Fixed.date(2026, 8, 5)
        )
        XCTAssertTrue(texts(report).contains("13일 중 1일 기록"))
    }

    func testVisitTooLongAgoFallsBackToFourWeeks() {
        // 반년 전 진료를 축으로 삼으면 요약이 아니라 목록이 된다.
        let report = content(lastVisit: Fixed.date(2026, 2, 1))
        XCTAssertEqual(report.titleKo, "더잔잔 · 4주 요약")
        XCTAssertEqual(report.periodKo, "2026년 7월 21일 – 2026년 8월 17일")
    }

    func testFutureVisitDoesNotAnchor() {
        // 아직 안 간 진료는 시작점이 될 수 없다.
        let report = content(lastVisit: Fixed.date(2026, 9, 1))
        XCTAssertEqual(report.titleKo, "더잔잔 · 4주 요약")
    }

    // MARK: - 용량 변경

    func testDoseChangeIsListedAsWritten() {
        let report = content(doseChanges: [
            DoseChange(
                medicationID: Fixed.medA,
                changedAt: Fixed.date(2026, 8, 10),
                fromText: "5mg",
                toText: "10mg",
                note: "저녁으로 옮김"
            )
        ])
        XCTAssertTrue(texts(report).contains("8월 10일 · 에스시탈로프람 5mg → 10mg"))
        XCTAssertTrue(texts(report).contains("저녁으로 옮김"))
    }

    func testDoseChangeOutsideWindowIsIgnoredAndSectionDisappears() {
        let report = content(doseChanges: [
            DoseChange(
                medicationID: Fixed.medA,
                changedAt: Fixed.date(2026, 6, 1),
                fromText: "5mg",
                toText: "10mg"
            )
        ])
        XCTAssertFalse(texts(report).contains("용량 변경"))
    }

    func testDoseChangeWithoutPreviousTextSaysOnlyTheNewOne() {
        let change = DoseChange(
            medicationID: Fixed.medA,
            changedAt: Fixed.date(2026, 8, 10),
            fromText: "",
            toText: "10mg"
        )
        XCTAssertEqual(change.arrowTextKo, "10mg")
        let report = content(doseChanges: [change])
        XCTAssertTrue(texts(report).contains("8월 10일 · 에스시탈로프람 10mg"))
    }

    // MARK: - 꿈

    func testDreamSectionCountsScalesAndCarriesNotes() {
        let checkIns = [
            CheckIn(
                date: Fixed.date(2026, 8, 14),
                mood: .init(0),
                dreamed: true,
                dreamVividness: 3,
                nightmare: true,
                dreamNote: "쫓기는 꿈"
            ),
            CheckIn(date: Fixed.date(2026, 8, 15), mood: .init(0), dreamed: true, dreamVividness: 2),
            CheckIn(date: Fixed.date(2026, 8, 16), mood: .init(1))
        ]
        let report = content(checkIns: checkIns)
        XCTAssertTrue(texts(report).contains("꿈을 기록한 날 2일 · 아주 생생함 1일 · 악몽 1일"))
        XCTAssertTrue(texts(report).contains("8월 14일 · 쫓기는 꿈"))
    }

    // MARK: - 생활

    func testLifestyleCountsAlcoholAndSmokingDays() {
        let checkIns = [
            CheckIn(date: Fixed.date(2026, 8, 14), mood: .init(0), activities: ["alcohol"]),
            CheckIn(date: Fixed.date(2026, 8, 15), mood: .init(0), activities: ["alcohol", "smoking"]),
            CheckIn(date: Fixed.date(2026, 8, 16), mood: .init(0), activities: ["work"])
        ]
        let report = content(checkIns: checkIns)
        XCTAssertTrue(texts(report).contains("술 마신 날 2일 · 담배 피운 날 1일"))
    }

    func testNoLifestyleSectionWithoutAlcoholOrSmoking() {
        // "0일" 은 빈 칸 재촉이다. 둘 다 없으면 구역 자체가 없어야 한다.
        let report = content(checkIns: [
            CheckIn(date: Fixed.date(2026, 8, 16), mood: .init(0), activities: ["work"])
        ])
        XCTAssertFalse(texts(report).contains("생활"))
    }

    func testNoDreamsMeansNoDreamSection() {
        // "꿈: 없음" 은 빈 칸 재촉이다. 구역 자체가 없어야 한다.
        let report = content(checkIns: [CheckIn(date: Fixed.date(2026, 8, 16), mood: .init(0))])
        XCTAssertFalse(texts(report).contains("꿈"))
    }

    // MARK: - 복약

    func testEmptyPeriodSaysSoInsteadOfZeroPercent() {
        // 기록이 없는 것과 0% 는 완전히 다른 말이다.
        let report = content()
        XCTAssertTrue(texts(report).contains("이 기간에는 셀 기록이 없습니다."))
        XCTAssertFalse(texts(report).contains { $0.contains("복약률") })
    }

    func testCountsTakenSkippedUnrecorded() {
        let report = content(doses: Fixed.workedExampleDoses())
        // 14 복용 · 2 건너뜀 · 1 미기록.
        XCTAssertTrue(texts(report).contains("복용 14회 · 건너뜀 2회 · 미기록 1회"))
        XCTAssertTrue(texts(report).contains("복약률 82%"))
    }

    func testPercentRoundsDownNotUp() {
        // 실제보다 잘 지킨 것처럼 보이면 안 된다. 14/17 = 82.35% → 82%.
        XCTAssertEqual(ReportComposer.percentText(Fixed.decimal("0.8235")), "82%")
        XCTAssertEqual(ReportComposer.percentText(Fixed.decimal("0.999")), "99%")
        XCTAssertEqual(ReportComposer.percentText(1), "100%")
    }

    // MARK: - 약

    func testStoppedMedicationIsNotListed() {
        let stopped = [Medication(id: Fixed.medA, name: "에스시탈로프람", status: .stopped)]
        let report = content(medications: stopped)
        XCTAssertTrue(texts(report).contains("등록된 약이 없습니다."))
    }

    func testRemainingIsOmittedWhenStockWasNeverCounted() {
        // 재고를 한 번도 세지 않았는데 "남은 개수 0정" 이라고 적으면 거짓말이 된다.
        let report = content(doses: Fixed.workedExampleDoses())
        XCTAssertFalse(texts(report).contains { $0.contains("남은 개수") })
    }

    func testRemainingAppearsOnceStockExists() {
        let report = content(
            doses: Fixed.workedExampleDoses(),
            stock: Fixed.workedExampleStock()
        )
        // 8/1 에 28정, 14정 복용 → 14정.
        XCTAssertTrue(texts(report).contains { $0.contains("남은 개수 14정") })
    }

    func testAsNeededIsMarked() {
        let report = content()
        XCTAssertTrue(texts(report).contains { $0.contains("쿠에티아핀 25mg") && $0.contains("필요시") })
    }

    func testShortfallBeforeVisitIsNoted() {
        // 8/1 에 3정만 받아 두고 하루 1정이면 9/1 진료 전에 모자란다.
        let thin: [StockEvent] = [
            .refill(medicationID: Fixed.medA, quantity: 3, at: Fixed.date(2026, 8, 1, 9, 0))
        ]
        let report = content(
            doses: Fixed.workedExampleDoses(),
            stock: thin,
            nextVisit: Fixed.date(2026, 9, 1, 9, 0)
        )
        XCTAssertTrue(texts(report).contains { $0.contains("모자랍니다") })
    }

    // MARK: - 기분

    func testMoodCountsDaysNotAverage() {
        // 평균은 −3~+3 을 섞어 놓아 뜻이 흐려진다. 가장 자주 고른 값 하나만 적는다.
        let checkIns = [
            CheckIn(date: Fixed.date(2026, 8, 14), mood: .init(-1)),
            CheckIn(date: Fixed.date(2026, 8, 15), mood: .init(-1)),
            CheckIn(date: Fixed.date(2026, 8, 16), mood: .init(2))
        ]
        let report = content(checkIns: checkIns)
        XCTAssertTrue(texts(report).contains("28일 중 3일 기록"))
        XCTAssertTrue(texts(report).contains("가장 자주 고른 기분: 조금 힘듦 (2일)"))
        XCTAssertFalse(texts(report).contains { $0.contains("평균") })
    }

    func testMoodOutsideWindowIsIgnored() {
        let old = [CheckIn(date: Fixed.date(2026, 6, 1), mood: .init(3))]
        let report = content(checkIns: old)
        XCTAssertTrue(texts(report).contains("이 기간에는 기분 기록이 없습니다."))
    }

    // MARK: - 물어볼 것

    func testQuestionsSectionAppearsOnlyWhenWritten() {
        XCTAssertFalse(texts(content()).contains("의사에게 물어볼 것"))

        let report = content(questions: "  아침에 어지러운 게 약 때문일까요\n\n용량을 줄일 수 있을까요  ")
        XCTAssertTrue(texts(report).contains("의사에게 물어볼 것"))
        XCTAssertTrue(texts(report).contains("아침에 어지러운 게 약 때문일까요"))
        XCTAssertTrue(texts(report).contains("용량을 줄일 수 있을까요"))
    }

    // MARK: - 말투

    func testNoJudgementAndNoPressure() {
        let report = content(
            doses: Fixed.workedExampleDoses(),
            stock: Fixed.workedExampleStock(),
            checkIns: [CheckIn(date: Fixed.date(2026, 8, 16), mood: .init(-3))]
        )

        for line in texts(report) {
            XCTAssertFalse(line.isEmpty, "빈 줄이 종이에 남으면 안 됩니다.")
            XCTAssertFalse(line.contains("!"), "느낌표는 쓰지 않습니다: \(line)")
            for word in ["잘 지", "좋아졌", "나빠졌", "실패", "연속", "달성"] {
                XCTAssertFalse(line.contains(word), "판단하는 말이 들어갔습니다: \(line)")
            }
        }
    }
}
