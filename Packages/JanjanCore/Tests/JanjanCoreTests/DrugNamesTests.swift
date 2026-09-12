import XCTest
@testable import JanjanCore

/// 성분명 표기 대응의 규칙: 표에 정확히 있는 이름만 언어를 따라가고,
/// 사용자가 조금이라도 다르게 적은 이름은 그대로 둔다.
final class DrugNamesTests: XCTestCase {

    func testKnownGenericNamesFollowTheLanguage() {
        XCTAssertEqual(DrugNames.display("로라제팜", in: .english), "Lorazepam")
        XCTAssertEqual(DrugNames.display("에스시탈로프람", in: .english), "Escitalopram")
        XCTAssertEqual(DrugNames.display("쿠에티아핀", in: .english), "Quetiapine")
        XCTAssertEqual(DrugNames.display("라모트리진", in: .english), "Lamotrigine")

        // 반대 방향도 같은 표를 쓴다. 영문은 대소문자를 가리지 않는다.
        XCTAssertEqual(DrugNames.display("Lorazepam", in: .korean), "로라제팜")
        XCTAssertEqual(DrugNames.display("lorazepam", in: .korean), "로라제팜")
        XCTAssertEqual(DrugNames.display("Escitalopram", in: .korean), "에스시탈로프람")
    }

    func testUnknownOrCustomNamesStayExactlyAsWritten() {
        // 표에 없는 이름, 상품명, 용량을 붙여 적은 이름은 사용자의 글자 그대로다.
        XCTAssertEqual(DrugNames.display("마그네슘", in: .english), "마그네슘")
        XCTAssertEqual(DrugNames.display("로라제팜 0.5", in: .english), "로라제팜 0.5")
        XCTAssertEqual(DrugNames.display("아침약", in: .english), "아침약")
        XCTAssertEqual(DrugNames.display("Xanax", in: .korean), "Xanax")
    }

    func testWhitespaceDoesNotBreakTheMatchButIsPreserved() {
        XCTAssertEqual(DrugNames.display(" 로라제팜 ", in: .english), "Lorazepam")
    }

    func testSameLanguageIsIdentity() {
        XCTAssertEqual(DrugNames.display("로라제팜", in: .korean), "로라제팜")
        XCTAssertEqual(DrugNames.display("Lorazepam", in: .english), "Lorazepam")
    }

    func testLocalizedDisplayTitleKeepsStrength() {
        let med = Medication(name: "쿠에티아핀", strengthText: "25mg")
        XCTAssertEqual(med.localizedDisplayTitle(.english), "Quetiapine 25mg")
        XCTAssertEqual(med.localizedDisplayTitle(.korean), "쿠에티아핀 25mg")
        XCTAssertEqual(med.localizedName(.english), "Quetiapine")
    }

    func testTableIsCleanForTheScreen() {
        for (ko, en) in DrugNames.pairs {
            XCTAssertFalse(ko.isEmpty)
            XCTAssertFalse(en.isEmpty)
            XCTAssertFalse(en.contains("!"))
            // 영문 표기는 표시에 그대로 쓰이므로 첫 글자가 대문자여야 한다.
            XCTAssertTrue(en.first?.isUppercase == true, "\(en) 는 대문자로 시작해야 합니다")
        }
    }
}
