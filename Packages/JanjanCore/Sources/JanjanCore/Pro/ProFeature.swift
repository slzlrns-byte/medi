import Foundation

// Pro 의 경계와 상품 ID. StoreKit 을 import 하지 않는 순수 값이라
// 앱·워치·테스트 어디서나 같은 문자열을 쓴다.
//
// 상품 ID 는 App Store Connect 와 글자 하나까지 같아야 한다(심사 체크리스트 3.4).
// 코드에서 문자열을 흩뿌리지 않고 여기 한 곳만 본다.

/// 구독을 사면 열리는 기능들. 화면 문구는 `titleKo` 하나만 쓴다.
public enum ProFeature: String, CaseIterable, Sendable {
    case pharmacyScan
    case runOutForecast
    case detailedMoodDiary
    case drugLookup
    case watchApp
    case reports
    case iCloudSync
    case altIcons

    public var titleKo: String {
        switch self {
        case .pharmacyScan: return "약봉투 스캔"
        case .runOutForecast: return "소진 예측과 부족 알림"
        case .detailedMoodDiary: return "자세한 기분일기"
        case .drugLookup: return "약 알아보기"
        case .watchApp: return "Apple Watch 앱"
        case .reports: return "진료용 리포트"
        case .iCloudSync: return "iCloud 동기화"
        case .altIcons: return "대체 아이콘"
        }
    }

    /// 페이월에 적는 4줄. App Store Connect 의 구독 설명이 약속한 것과 같은 4개다
    /// (docs/decisions.md 2026-08-17 "Pro 구독 설명"). 순서까지 그 문장을 따른다.
    public static let launchHighlights: [ProFeature] = [
        .pharmacyScan,
        .runOutForecast,
        .detailedMoodDiary,
        .drugLookup
    ]
}

/// 구독 상품. 그룹 1개 · 상품 2개 · entitlement 이름 하나(`pro`).
public enum ProProduct {

    public static let monthly = "pro_monthly"
    public static let yearly = "pro_yearly"

    /// App Store Connect 의 구독 그룹 참조 이름.
    public static let groupName = "The잔잔 Pro"

    /// 상품을 불러올 때·권한을 확인할 때 쓰는 전체 목록. 연간을 먼저 보여 준다.
    public static let allIDs: [String] = [yearly, monthly]

    /// 애플이 정한 구독 관리 화면. 앱이 직접 해지 UI 를 만들지 않는다(3.1.2).
    public static let manageSubscriptionsURLString = "https://apps.apple.com/account/subscriptions"
}
