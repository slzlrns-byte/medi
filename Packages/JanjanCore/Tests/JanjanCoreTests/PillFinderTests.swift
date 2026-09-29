import XCTest
@testable import JanjanCore

/// 약 모양으로 찾기. 핵심은 셋이다:
/// 조건이 없으면 아무것도 들지 않고(전부 나열은 찾기가 아니다),
/// 각인은 표기 차이(공백·하이픈·대소문자)를 무시하고,
/// 각인이 정확히 맞는 후보가 늘 맨 앞에 선다.
final class PillFinderTests: XCTestCase {

    private let pills: [PillFinder.Pill] = [
        PillFinder.Pill(
            id: "1", name: "렉사프로정 10mg", strengthText: "10mg",
            shape: .oval, colorFront: .white, imprintFront: "F L", imprintBack: "10"
        ),
        PillFinder.Pill(
            id: "2", name: "자나팜정 0.25mg", strengthText: "0.25mg",
            shape: .oval, colorFront: .white, imprintFront: "XANAX 0.25"
        ),
        PillFinder.Pill(
            id: "3", name: "쿠에타핀정 25mg", strengthText: "25mg",
            shape: .round, colorFront: .pink, imprintFront: "Q25"
        ),
        PillFinder.Pill(
            id: "4", name: "스틸녹스정 10mg", strengthText: "10mg",
            shape: .oblong, colorFront: .white, colorBack: .pink, imprintFront: "SN10"
        )
    ]

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(PillFinder.search(PillFinder.Query(), in: pills).isEmpty)
    }

    func testImprintIgnoresSpacingHyphensAndCase() {
        // "fl" 도 "F-L" 도 "F L" 각인을 찾는다.
        for typed in ["fl", "F-L", "f l"] {
            let found = PillFinder.search(PillFinder.Query(imprint: typed), in: pills)
            XCTAssertEqual(found.map(\.id), ["1"], "입력 '\(typed)' 이 F L 각인을 찾아야 합니다")
        }
    }

    func testExactImprintOutranksPartialMatch() {
        // "10" 은 1번(뒷면 정확 일치)이 4번(SN10 포함)보다 앞에 와야 한다.
        let found = PillFinder.search(PillFinder.Query(imprint: "10"), in: pills)
        XCTAssertEqual(found.first?.id, "1")
        XCTAssertTrue(found.contains { $0.id == "4" })
    }

    func testColorMatchesEitherSide() {
        // 분홍을 고르면 앞면이 분홍인 3번과 뒷면이 분홍인 4번이 함께 나온다.
        let found = PillFinder.search(PillFinder.Query(color: .pink), in: pills)
        XCTAssertEqual(Set(found.map(\.id)), ["3", "4"])
    }

    func testShapeAndColorNarrowTogether() {
        let query = PillFinder.Query(shape: .oval, color: .white)
        let found = PillFinder.search(query, in: pills)
        XCTAssertEqual(Set(found.map(\.id)), ["1", "2"])
    }

    func testResultCountIsBounded() {
        let many = (0..<100).map { index in
            PillFinder.Pill(
                id: "m\(index)", name: "약 \(index)",
                shape: .round, colorFront: .white
            )
        }
        let found = PillFinder.search(PillFinder.Query(shape: .round), in: many)
        XCTAssertEqual(found.count, PillFinder.maxResults)
    }

    func testLabelsSpeakBothLanguages() {
        XCTAssertEqual(PillFinder.Shape.round.label(.korean), "원형")
        XCTAssertEqual(PillFinder.Shape.round.label(.english), "Round")
        XCTAssertEqual(PillFinder.PillColor.white.label(.korean), "하양")
        XCTAssertEqual(PillFinder.PillColor.white.label(.english), "White")
    }
}
