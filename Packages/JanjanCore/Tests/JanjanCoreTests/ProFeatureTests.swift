import XCTest
@testable import JanjanCore

/// 상품 ID 오타와 페이월 문구 누락은 심사에서 바로 걸린다(체크리스트 3.3 · 3.4).
/// 값이 하나뿐이라 테스트도 세 줄짜리로 충분하다.
final class ProFeatureTests: XCTestCase {

    func testLaunchHighlightsAreWhatTheAppActuallyLocks() {
        XCTAssertEqual(
            ProFeature.launchHighlights,
            [.pharmacyScan, .runOutForecast, .reports]
        )
        XCTAssertEqual(ProFeature.launchHighlights.map(\.titleKo).first, "약봉투 스캔")
    }

    /// 페이월에 적은 것은 앱에서 실제로 잠겨 있어야 한다(2.3.1 · 3.1.2).
    /// 아직 만들지 않은 기능과 무료로 열어 둔 기능은 여기 들어오면 안 된다.
    func testUnbuiltAndFreeFeaturesAreNotAdvertised() {
        // 약 알아보기는 v1 에 없다. 만들기 전에는 페이월에 적지 않는다.
        XCTAssertFalse(ProFeature.launchHighlights.contains(.drugLookup))
        // 기분 기록은 잠그지 않기로 했다. 잠그지 않은 것을 팔지 않는다.
        XCTAssertFalse(ProFeature.launchHighlights.contains(.detailedMoodDiary))
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
