import XCTest
@testable import JanjanCore

/// 상품 ID 오타와 페이월 문구 누락은 심사에서 바로 걸린다(체크리스트 3.3 · 3.4).
/// 값이 하나뿐이라 테스트도 세 줄짜리로 충분하다.
final class ProFeatureTests: XCTestCase {

    func testLaunchHighlightsAreTheFourPromisedInTheStoreDescription() {
        XCTAssertEqual(ProFeature.launchHighlights.count, 4)
        XCTAssertEqual(
            ProFeature.launchHighlights,
            [.pharmacyScan, .runOutForecast, .detailedMoodDiary, .drugLookup]
        )
        XCTAssertEqual(ProFeature.launchHighlights.map(\.titleKo).first, "약봉투 스캔")
    }

    func testProductIdentifiersMatchAppStoreConnectExactly() {
        XCTAssertEqual(ProProduct.monthly, "pro_monthly")
        XCTAssertEqual(ProProduct.yearly, "pro_yearly")
        XCTAssertEqual(ProProduct.groupName, "The잔잔 Pro")
        XCTAssertEqual(ProProduct.allIDs, ["pro_yearly", "pro_monthly"])
        XCTAssertEqual(
            ProProduct.manageSubscriptionsURLString,
            "https://apps.apple.com/account/subscriptions"
        )
    }

    func testEveryFeatureHasKoreanTitle() {
        XCTAssertEqual(ProFeature.allCases.count, 8)
        for feature in ProFeature.allCases {
            XCTAssertFalse(feature.titleKo.isEmpty, "\(feature) 문구가 비어 있다")
            XCTAssertFalse(feature.rawValue.isEmpty)
        }
        // 문구가 서로 겹치면 페이월에서 같은 줄이 두 번 보인다.
        XCTAssertEqual(Set(ProFeature.allCases.map(\.titleKo)).count, ProFeature.allCases.count)
    }
}
