import Foundation

// Pro 의 경계와 상품 ID. StoreKit 을 import 하지 않는 순수 값이라
// 앱·워치·테스트 어디서나 같은 문자열을 쓴다.
//
// 상품 ID 는 App Store Connect 와 글자 하나까지 같아야 한다(심사 체크리스트 3.4).
// 코드에서 문자열을 흩뿌리지 않고 여기 한 곳만 본다.

/// 구독을 사면 열리는 기능들. 화면 문구는 `titleKo` 하나만 쓴다.
public enum ProFeature: String, CaseIterable, Sendable {
    case pharmacyScan
    case pillFinder
    case patternView
    case smartFollowUp
    case proThemes
    case runOutForecast
    case hideNames
    case doseChangeCompare
    case visitHistory
    case noAds
    case detailedMoodDiary
    case watchApp
    case reports
    case iCloudSync
    case altIcons

    public var titleKo: String {
        switch self {
        case .pharmacyScan: return "약봉투 스캔"
        case .pillFinder: return "약 모양으로 찾기"
        case .patternView: return "패턴 보기"
        case .smartFollowUp: return "똑똑한 재알림"
        case .proThemes: return "Pro 테마"
        case .runOutForecast: return "소진 예측"
        case .hideNames: return "약 이름 가리기"
        case .doseChangeCompare: return "용량 변경 전후 비교"
        case .visitHistory: return "지난 진료 기록"
        case .noAds: return "광고 없이"
        case .detailedMoodDiary: return "자세한 기분일기"
        case .watchApp: return "Apple Watch 앱"
        case .reports: return "진료용 리포트"
        case .iCloudSync: return "iCloud 동기화"
        case .altIcons: return "대체 아이콘"
        }
    }

    public var titleEn: String {
        switch self {
        case .pharmacyScan: return "Pharmacy bag scan"
        case .pillFinder: return "Find by pill appearance"
        case .patternView: return "Pattern view"
        case .smartFollowUp: return "Smart re-reminders"
        case .proThemes: return "Pro themes"
        case .runOutForecast: return "Run-out forecast"
        case .hideNames: return "Hide medication names"
        case .doseChangeCompare: return "Dose change comparison"
        case .visitHistory: return "Visit history"
        case .noAds: return "No ads"
        case .detailedMoodDiary: return "Detailed mood journal"
        case .watchApp: return "Apple Watch app"
        case .reports: return "Visit report"
        case .iCloudSync: return "iCloud sync"
        case .altIcons: return "Alternate icons"
        }
    }

    public func title(_ language: JanjanLanguage) -> String {
        language == .english ? titleEn : titleKo
    }

    /// 페이월에서 줄을 묶는 이름. 열 줄을 그냥 늘어놓으면 읽는 사람이
    /// 아무것도 기억하지 못한다 - 무엇을 위한 것인지로 묶는다(2026-09-19).
    public enum Group: String, CaseIterable, Sendable {
        case guarding
        case clinic
        case easier
        case mine

        public var titleKo: String {
            switch self {
            case .guarding: return "놓치지 않게"
            case .clinic: return "진료실에 들고 갈 것"
            case .easier: return "손이 덜 가게"
            case .mine: return "내게 맞게"
            }
        }

        public var titleEn: String {
            switch self {
            case .guarding: return "So you don't miss it"
            case .clinic: return "To bring to your visit"
            case .easier: return "Less to do by hand"
            case .mine: return "Made yours"
            }
        }

        public func title(_ language: JanjanLanguage) -> String {
            language == .english ? titleEn : titleKo
        }
    }

    public var group: Group {
        switch self {
        case .smartFollowUp, .runOutForecast, .watchApp:
            return .guarding
        case .patternView, .doseChangeCompare, .visitHistory, .reports:
            return .clinic
        case .pharmacyScan, .pillFinder, .iCloudSync:
            return .easier
        case .noAds, .hideNames, .proThemes, .detailedMoodDiary, .altIcons:
            return .mine
        }
    }

    /// 페이월에 적는 줄. **여기 적은 것은 앱에서 실제로 잠겨 있어야 한다.**
    ///
    /// 원래 넷이었는데(2026-08-17 결정) 셋을 뺐다.
    ///   · 자세한 기분일기 — 잠그지 않기로 했다. 정신과 기록 앱에서 기분 기록을
    ///     잠그면 이 앱이 있는 이유와 부딪힌다. 무료로 열어 둔다.
    ///   · 약 알아보기 — 뺐다. 식약처 이상반응 원문을 펼쳐 보이는 대신
    ///     담당의에게 들은 몇 줄을 적어 두는 쪽으로 갔다(2026-08-26 결정).
    ///     `MedicationNote` 가 그 자리를 대신하고, 그것은 무료다.
    ///   · 진료용 리포트 — 무료로 열었다(2026-09-10, 강점 결정서). 이 앱의
    ///     포지셔닝이 "진료실 준비 노트" 인데 그 한 장을 잠그면 자리 자체를
    ///     잠그는 셈이다. 워치 앱은 여전히 Pro 다.
    ///
    /// **App Store Connect 의 구독 설명도 이 목록과 같아야 한다.** 한쪽만 고치면
    /// 앱과 스토어가 서로 다른 약속을 하게 된다.
    ///
    /// 패턴 보기·똑똑한 재알림·Pro 테마·지난 진료 기록(2026-09-19)을 더해 열이
    /// 됐고, 광고 도입과 함께 "광고 없이" 가 맨 앞에 붙어 열하나가 됐다.
    /// 그것을 첫 줄에 둔 이유: 나머지 열은 기록이 쌓여야 쓸모가 생기는데,
    /// 광고 없이는 **무료 사용자가 설치 첫날부터 매일 체감하는 유일한 항목**이다.
    ///
    /// ASC 구독 설명은 45자 제한이라 다 못 적어 몇 항목만 적는다 - 설명이
    /// 약속한 것이 실제 잠금의 부분집합이면 어긋남이 아니다(3.10).
    public static let launchHighlights: [ProFeature] = [
        .noAds,
        .pharmacyScan,
        .pillFinder,
        .patternView,
        .smartFollowUp,
        .runOutForecast,
        .doseChangeCompare,
        .visitHistory,
        .hideNames,
        .proThemes,
        .watchApp
    ]

    /// 페이월이 그리는 차례. 빈 묶음은 빼고, 모든 줄이 정확히 한 묶음에 속한다.
    public static var launchGroups: [(group: Group, features: [ProFeature])] {
        Group.allCases.compactMap { group in
            let features = launchHighlights.filter { $0.group == group }
            return features.isEmpty ? nil : (group, features)
        }
    }
}

/// Pro 상품. 구독 그룹 1개(월간·연간) + 비소모성 평생 이용권 1개.
/// 어느 쪽이든 권한 이름은 하나(`pro`)다 - 화면은 isPro 만 본다.
public enum ProProduct {

    public static let monthly = "pro_monthly"
    public static let yearly = "pro_yearly"
    /// 평생 이용권(2026-09-19 결정). "구독은 싫지만 돈은 내겠다" 는 복약앱 특유의
    /// 정서를 받는 비소모성 상품이고, 연간 가격의 앵커 역할도 한다.
    public static let lifetime = "pro_lifetime"

    /// App Store Connect 의 구독 그룹 참조 이름.
    public static let groupName = "The잔잔 Pro"

    /// 상품을 불러올 때·권한을 확인할 때 쓰는 전체 목록. 연간을 먼저 보여 준다.
    public static let allIDs: [String] = [yearly, monthly, lifetime]

    /// 애플이 정한 구독 관리 화면. 앱이 직접 해지 UI 를 만들지 않는다(3.1.2).
    public static let manageSubscriptionsURLString = "https://apps.apple.com/account/subscriptions"
}
