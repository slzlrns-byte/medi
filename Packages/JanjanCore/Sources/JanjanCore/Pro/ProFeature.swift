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
    case watchApp
    case reports
    case iCloudSync
    case altIcons

    public var titleKo: String {
        switch self {
        case .pharmacyScan: return "약봉투 스캔"
        case .runOutForecast: return "소진 예측과 부족 알림"
        case .detailedMoodDiary: return "자세한 기분일기"
        case .watchApp: return "Apple Watch 앱"
        case .reports: return "진료용 리포트"
        case .iCloudSync: return "iCloud 동기화"
        case .altIcons: return "대체 아이콘"
        }
    }

    /// 페이월에 적는 줄. **여기 적은 것은 앱에서 실제로 잠겨 있어야 한다.**
    ///
    /// 원래 넷이었는데(2026-08-17 결정) 둘을 뺐다.
    ///   · 자세한 기분일기 — 잠그지 않기로 했다. 정신과 기록 앱에서 기분 기록을
    ///     잠그면 이 앱이 있는 이유와 부딪힌다. 무료로 열어 둔다.
    ///   · 약 알아보기 — 뺐다. 식약처 이상반응 원문을 펼쳐 보이는 대신
    ///     담당의에게 들은 몇 줄을 적어 두는 쪽으로 갔다(2026-08-26 결정).
    ///     `MedicationNote` 가 그 자리를 대신하고, 그것은 무료다.
    ///
    /// **App Store Connect 의 구독 설명도 이 목록과 같아야 한다.** 한쪽만 고치면
    /// 앱과 스토어가 서로 다른 약속을 하게 된다.
    public static let launchHighlights: [ProFeature] = [
        .pharmacyScan,
        .runOutForecast,
        .reports
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
