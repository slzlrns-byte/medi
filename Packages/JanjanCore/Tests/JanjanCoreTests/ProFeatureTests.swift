import XCTest
@testable import JanjanCore

/// 상품 ID 오타와 페이월 문구 누락은 심사에서 바로 걸린다(체크리스트 3.3 · 3.4).
/// 값이 하나뿐이라 테스트도 세 줄짜리로 충분하다.
final class ProFeatureTests: XCTestCase {

    func testLaunchHighlightsAreWhatTheAppActuallyLocks() {
        XCTAssertEqual(
            ProFeature.launchHighlights,
            [.noAds, .pharmacyScan, .pillFinder, .patternView, .smartFollowUp, .runOutForecast,
             .doseChangeCompare, .visitHistory, .hideNames, .proThemes, .watchApp]
        )
        XCTAssertEqual(ProFeature.launchHighlights.map(\.titleKo).first, "광고 없이")
    }

    /// 페이월에 적은 것은 앱에서 실제로 잠겨 있어야 한다(2.3.1 · 3.1.2).
    /// 아직 만들지 않은 기능과 무료로 열어 둔 기능은 여기 들어오면 안 된다.
    func testUnbuiltAndFreeFeaturesAreNotAdvertised() {
        // 기분 기록은 잠그지 않기로 했다. 잠그지 않은 것을 팔지 않는다.
        XCTAssertFalse(ProFeature.launchHighlights.contains(.detailedMoodDiary))
        // 진료용 리포트는 무료로 열었다(2026-09-10) — 진료실 준비 노트가 이 앱의
        // 자리라서다. 무료로 연 것이 페이월에 다시 들어오면 거짓말이 된다.
        XCTAssertFalse(ProFeature.launchHighlights.contains(.reports))
    }

    /// 페이월은 묶음으로 그린다. 한 줄이 두 묶음에 들어가거나 어느 묶음에도
    /// 없으면 화면에서 조용히 사라지거나 두 번 보인다.
    func testEveryAdvertisedFeatureAppearsInExactlyOneGroup() {
        // 페이월이 실제로 그리는 것은 launchGroups 다. 평평한 배열의 첫 줄만
        // 보면 "광고 없이" 가 맨 마지막 묶음에 묻혀도 테스트가 초록이다
        // (QA 2026-09-19 - 실제로 그렇게 묻혀 있었다).
        XCTAssertEqual(ProFeature.launchGroups.first?.features.first, .noAds)

        let grouped = ProFeature.launchGroups.flatMap(\.features)
        XCTAssertEqual(grouped.count, ProFeature.launchHighlights.count)
        XCTAssertEqual(Set(grouped), Set(ProFeature.launchHighlights))
        for (group, features) in ProFeature.launchGroups {
            XCTAssertFalse(features.isEmpty, "\(group) 묶음이 비어 있다")
            XCTAssertFalse(group.titleKo.isEmpty)
            XCTAssertFalse(group.titleEn.isEmpty)
        }
    }

    func testProductIdentifiersMatchAppStoreConnectExactly() {
        XCTAssertEqual(ProProduct.monthly, "pro_monthly")
        XCTAssertEqual(ProProduct.yearly, "pro_yearly")
        XCTAssertEqual(ProProduct.lifetime, "pro_lifetime")
        XCTAssertEqual(ProProduct.groupName, "The잔잔 Pro")
        XCTAssertEqual(ProProduct.allIDs, ["pro_yearly", "pro_monthly", "pro_lifetime"])
        XCTAssertEqual(
            ProProduct.manageSubscriptionsURLString,
            "https://apps.apple.com/account/subscriptions"
        )
    }

    func testEveryFeatureHasKoreanTitle() {
        XCTAssertEqual(ProFeature.allCases.count, 15)
        for feature in ProFeature.allCases {
            XCTAssertFalse(feature.titleKo.isEmpty, "\(feature) 문구가 비어 있다")
            XCTAssertFalse(feature.rawValue.isEmpty)
        }
        // 문구가 서로 겹치면 페이월에서 같은 줄이 두 번 보인다.
        XCTAssertEqual(Set(ProFeature.allCases.map(\.titleKo)).count, ProFeature.allCases.count)
    }
}
