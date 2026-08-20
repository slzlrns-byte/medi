import XCTest
@testable import JanjanCore

/// 약봉투에서 읽어 낸 글자를 약 후보로 접는 규칙.
///
/// 이 파서는 **틀려도 되지만 조용히 틀리면 안 된다.** 여기서 나온 값은 반드시
/// 사용자가 보고 고치는 화면을 거치므로, 후보를 하나 놓치는 것보다
/// "조제일자" 를 약 이름이라고 우기는 쪽이 훨씬 나쁘다.
final class PharmacyLabelParserTests: XCTestCase {

    /// 흔한 조제 봉투 한 장을 통째로 넣어 본다.
    private let realisticLabel = [
        "잔잔약국",
        "조제일자 2026-08-17",
        "환자명 홍길동",
        "쿠에티아핀정25mg 1정 취침전",
        "라믹탈정 100mg 1정 아침",
        "에스시탈로프람정 10mg",
        "1일 1회 28일분",
        "용법: 식후 30분에 복용",
        "약사 김OO"
    ]

    private func names(_ lines: [String]) -> [String] {
        PharmacyLabelParser.candidates(from: lines).map(\.name)
    }

    // MARK: - 통째로

    func testRealisticLabelYieldsOnlyMedications() {
        let candidates = PharmacyLabelParser.candidates(from: realisticLabel)
        XCTAssertEqual(
            candidates.map(\.name),
            ["쿠에티아핀정", "라믹탈정", "에스시탈로프람정"]
        )
        XCTAssertEqual(
            candidates.map(\.strengthText),
            ["25mg", "100mg", "10mg"]
        )
    }

    func testOrderFollowsTheLabel() {
        let candidates = PharmacyLabelParser.candidates(from: realisticLabel)
        XCTAssertEqual(candidates.first?.name, "쿠에티아핀정")
        XCTAssertEqual(candidates.last?.name, "에스시탈로프람정")
    }

    func testSourceLineIsKeptForTheConfirmationScreen() {
        // 확인 화면은 원래 줄을 함께 보여 준다. 파서가 뭘 보고 그렇게 읽었는지
        // 사용자가 알아야 고칠 수 있다.
        let candidates = PharmacyLabelParser.candidates(from: realisticLabel)
        XCTAssertEqual(candidates.first?.sourceLine, "쿠에티아핀정25mg 1정 취침전")
    }

    // MARK: - 걸러 내는 것

    func testPharmacyBoilerplateIsDropped() {
        for line in ["잔잔약국", "조제일자 2026-08-17", "환자명 홍길동", "약사 김OO", "1일 1회 28일분"] {
            XCTAssertTrue(names([line]).isEmpty, "약이 아닌 줄이 올라왔습니다: \(line)")
        }
    }

    func testDateLineIsNeverAMedication() {
        XCTAssertTrue(names(["2026-08-17"]).isEmpty)
        XCTAssertTrue(names(["2026.08.17 발행"]).isEmpty)
    }

    func testDigitsOnlyLineIsDropped() {
        XCTAssertTrue(names(["25", "1 2 3", "---"]).isEmpty)
    }

    func testTooShortAndTooLongLinesAreDropped() {
        XCTAssertTrue(names(["정"]).isEmpty)
        XCTAssertTrue(names([String(repeating: "가", count: 80) + " 10mg"]).isEmpty)
    }

    // MARK: - 이름과 용량 나누기

    func testStrengthStuckToTheNameIsSeparated() {
        let candidates = PharmacyLabelParser.candidates(from: ["아빌리파이정10mg"])
        XCTAssertEqual(candidates.first?.name, "아빌리파이정")
        XCTAssertEqual(candidates.first?.strengthText, "10mg")
    }

    func testSpacedAndCommaStrengths() {
        XCTAssertEqual(PharmacyLabelParser.strength(in: "쿠에티아핀 0.5 mg"), "0.5mg")
        XCTAssertEqual(PharmacyLabelParser.strength(in: "쿠에티아핀 12,5mg"), "12.5mg")
    }

    func testSquareUnitCharacterIsRead() {
        // ㎎ 는 글자가 아니라 기호라서 단어 경계 규칙으로는 잡히지 않는다.
        XCTAssertEqual(PharmacyLabelParser.strength(in: "라믹탈정 100㎎ 1정"), "100㎎")
        XCTAssertEqual(PharmacyLabelParser.candidates(from: ["라믹탈정 100㎎ 1정"]).first?.name, "라믹탈정")
    }

    func testKoreanUnitIsRead() {
        XCTAssertEqual(PharmacyLabelParser.strength(in: "아빌리파이정 10밀리그램"), "10밀리그램")
    }

    func testDosageAndTimingAreStrippedFromTheName() {
        let candidates = PharmacyLabelParser.candidates(from: ["쿠에티아핀정 25mg 1정 취침전"])
        XCTAssertEqual(candidates.first?.name, "쿠에티아핀정")
    }

    func testParenthesesAreStrippedFromTheName() {
        let candidates = PharmacyLabelParser.candidates(from: ["라믹탈정(라모트리진) 100mg"])
        XCTAssertEqual(candidates.first?.name, "라믹탈정")
    }

    func testMedicationWithoutStrengthIsStillOfferedWhenItLooksLikeOne() {
        // 용량이 안 찍힌 봉투도 있다. 제형으로 끝나면 후보로 올린다.
        let candidates = PharmacyLabelParser.candidates(from: ["인데놀정"])
        XCTAssertEqual(candidates.first?.name, "인데놀정")
        XCTAssertEqual(candidates.first?.strengthText, "")
    }

    // MARK: - 중복

    func testSameMedicationListedTwiceAppearsOnce() {
        // 요일별 칸이 있는 봉투는 같은 약을 여러 번 찍는다.
        let repeated = [
            "쿠에티아핀정 25mg",
            "쿠에티아핀정 25mg",
            "쿠에티아핀정 50mg"
        ]
        let candidates = PharmacyLabelParser.candidates(from: repeated)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(candidates.map(\.strengthText), ["25mg", "50mg"])
    }

    // MARK: - 정리

    func testNormalizeCollapsesWhitespaceWithoutLosingCharacters() {
        XCTAssertEqual(
            PharmacyLabelParser.normalize("  쿠에티아핀정   25mg  "),
            "쿠에티아핀정 25mg"
        )
    }

    func testEmptyInputIsEmptyOutput() {
        XCTAssertTrue(PharmacyLabelParser.candidates(from: []).isEmpty)
        XCTAssertTrue(PharmacyLabelParser.candidates(from: ["", "   "]).isEmpty)
    }

    // MARK: - 설명문은 약 이름이 아니다

    func testInstructionLineWithAStrengthIsNotAMedication() {
        // 용량이 적혀 있다는 이유만으로 후보로 올리면, 용량과 용법 숫자를 떼어 낸 뒤
        // "에 함유" 같은 부스러기가 확인 화면에 약 이름처럼 올라온다.
        let lines = ["1회 1정에 500mg 함유", "쿠에티아핀정 25mg"]
        let candidates = PharmacyLabelParser.candidates(from: lines)
        XCTAssertEqual(candidates.map(\.name), ["쿠에티아핀정"])
    }

    func testParticleFragmentsAreRejected() {
        XCTAssertFalse(PharmacyLabelParser.isPlausibleName("에 함유"))
        XCTAssertFalse(PharmacyLabelParser.isPlausibleName("를 복용"))
        XCTAssertFalse(PharmacyLabelParser.isPlausibleName("1"))
        XCTAssertFalse(PharmacyLabelParser.isPlausibleName("· - ·"))
    }

    func testRealNamesStillPass() {
        // 걸러 내는 규칙을 세게 잡다가 진짜 약을 떨어뜨리면 더 나쁘다.
        for name in ["쿠에티아핀정", "라믹탈", "escitalopram", "인데놀", "아빌리파이정"] {
            XCTAssertTrue(PharmacyLabelParser.isPlausibleName(name), name)
        }
    }
}
