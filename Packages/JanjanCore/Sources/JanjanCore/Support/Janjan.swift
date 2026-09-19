import Foundation

/// 앱 전체가 공유하는 상수. 문구는 존댓말, 이모지 없음, 한 문장에 한 정보.
public enum Janjan {

    public static let appNameKo = "더잔잔"
    public static let appNameEn = "The Janjan"
    public static let sloganKo = "더 잔잔한 하루를 위해"
    public static let sloganEn = "For a calmer day"

    public static func slogan(_ language: JanjanLanguage) -> String {
        language == .english ? sloganEn : sloganKo
    }

    /// iCloud 컨테이너. entitlements 파일과 반드시 같아야 한다.
    public static let cloudKitContainerID = "iCloud.com.thejanjan.app"

    public static let appBundleID = "com.thejanjan.app"
    public static let watchBundleID = "com.thejanjan.app.watchkitapp"
    public static let widgetBundleID = "com.thejanjan.app.widgets"

    /// 앱과 위젯이 **같은 저장소**를 열기 위한 App Group.
    ///
    /// 위젯은 별도 프로세스라 앱의 기본 저장 위치에 손이 닿지 않는다. 그룹 컨테이너에
    /// 두어야 둘이 같은 파일을 본다. 위젯의 '먹었어요' 가 진짜 기록이 되는 것도
    /// 이것 덕분이다 — 앱을 열 때까지 기다렸다 반영하는 방식이면, 앱을 안 여는 날의
    /// 기록은 늦거나 사라진다.
    ///
    /// 두 타깃의 entitlements 에 같은 값이 들어 있어야 하고, Apple Developer 의
    /// App ID 두 개 모두에 App Groups capability 가 켜져 있어야 서명이 통과한다.
    public static let appGroupID = "group.com.thejanjan.app"

    /// 위젯이 앱을 열 때 쓰는 주소 체계. Info.plist 의 CFBundleURLSchemes 와
    /// 글자 하나까지 같아야 한다 - 다르면 버튼이 조용히 아무 일도 하지 않는다.
    public static let urlScheme = "thejanjan"

    /// 무료 위젯의 "먹었어요" 가 여는 자리. 앱은 기본으로 오늘 탭에서 열리고,
    /// 그 시간대 카드가 바로 거기 있다. 시간대 키를 실어 두는 것은 나중에
    /// 그 카드로 더 정확히 데려갈 때를 위해서다.
    public static func logSlotURL(slotKey: String) -> URL {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "log"
        components.queryItems = [URLQueryItem(name: "slot", value: slotKey)]
        // 구성 요소가 전부 상수라 실패할 수 없지만, 강제 해제는 두지 않는다.
        return components.url ?? URL(string: "\(urlScheme)://log")!
    }

    /// 정책 페이지. 원본은 저장소의 `docs/site/` 이고 GitHub Pages 로 낸다.
    /// App Store Connect 의 URL 칸과 앱 설정 화면이 같은 주소를 쓴다.
    // **커스텀 도메인을 쓴다**(docs/CNAME = janjan.loviti.app).
    // github.io 주소도 이쪽으로 넘어가지만, 앱과 App Store Connect 가 같은
    // 주소를 말해야 심사관이 보는 것과 앱에서 열리는 것이 일치한다.
    // 도메인을 바꾸면 여기와 docs/CNAME 과 ASC 세 곳을 함께 고친다.
    public static let privacyPolicyURLString = "https://janjan.loviti.app/site/privacy.html"
    public static let supportURLString = "https://janjan.loviti.app/site/support.html"
    public static let termsURLString = "https://janjan.loviti.app/site/terms.html"

    /// 앱 어디에도 진단·조언을 쓰지 않는다는 약속을 문장으로 고정해 둔다.
    public static let medicalDisclaimerKo =
        "이 앱은 의료 조언이 아닙니다. 복용 변경은 담당 의사와 상의해 주세요."

    public static let medicalDisclaimerEn =
        "This app does not give medical advice. Please talk with your doctor before changing your medication."

    public static func medicalDisclaimer(_ language: JanjanLanguage) -> String {
        language == .english ? medicalDisclaimerEn : medicalDisclaimerKo
    }

    public static func appName(_ language: JanjanLanguage) -> String {
        language == .english ? appNameEn : appNameKo
    }

    /// 위기 상담 연락처. 안전 카드와 설정 화면에서 같은 값을 쓴다.
    public struct CrisisContact: Hashable, Sendable, Identifiable {
        public let id: String
        public let titleKo: String
        public let subtitleKo: String
        public let titleEn: String
        public let subtitleEn: String
        public let number: String

        public init(
            id: String,
            titleKo: String,
            subtitleKo: String,
            titleEn: String,
            subtitleEn: String,
            number: String
        ) {
            self.id = id
            self.titleKo = titleKo
            self.subtitleKo = subtitleKo
            self.titleEn = titleEn
            self.subtitleEn = subtitleEn
            self.number = number
        }

        public func title(_ language: JanjanLanguage) -> String {
            language == .english ? titleEn : titleKo
        }

        public func subtitle(_ language: JanjanLanguage) -> String {
            language == .english ? subtitleEn : subtitleKo
        }

        /// tel: URL 에 쓸 수 있게 하이픈을 뗀 번호.
        public var dialDigits: String {
            number.filter(\.isNumber)
        }
    }

    public static let crisisContactsKR: [CrisisContact] = [
        CrisisContact(
            id: "suicide_prevention",
            titleKo: "자살예방상담전화",
            subtitleKo: "24시간 언제든",
            titleEn: "Suicide prevention hotline (Korea)",
            subtitleEn: "Any time, 24 hours",
            number: "109"
        ),
        CrisisContact(
            id: "mental_health_crisis",
            titleKo: "정신건강위기상담",
            subtitleKo: "24시간 언제든",
            titleEn: "Mental health crisis line (Korea)",
            subtitleEn: "Any time, 24 hours",
            number: "1577-0199"
        )
    ]

    /// 지역별 위기 상담 연락처.
    ///
    /// **검증한 번호만 싣는다.** 틀린 번호를 내미는 것은 아무 번호도 없는 것보다 나쁘다.
    /// 아직 한국만 확인했고, 다른 지역에서는 빈 목록을 돌려주고 화면이
    /// `safetyCardWithoutContactsKo` 로 떨어진다.
    public static func crisisContacts(regionCode: String?) -> [CrisisContact] {
        switch regionCode?.uppercased() {
        case "KR": return crisisContactsKR
        default: return []
        }
    }

    /// 기기의 지역 설정에 맞는 연락처.
    public static var crisisContactsForCurrentRegion: [CrisisContact] {
        crisisContacts(regionCode: Locale.current.region?.identifier)
    }

    /// 안전 카드에 쓰는 문구. 경고도 진단도 아니고, 연락처를 조용히 내미는 한 문장.
    public static let safetyCardMessageKo =
        "기록은 그대로 저장됐어요. 지금 이야기할 곳이 필요하면 여기로 연락할 수 있어요."

    public static let safetyCardMessageEn =
        "Your note was saved as written. If you need someone to talk to right now, you can reach out here."

    public static func safetyCardMessage(_ language: JanjanLanguage) -> String {
        language == .english ? safetyCardMessageEn : safetyCardMessageKo
    }

    /// 번호를 확인하지 못한 지역에서 쓰는 문장. 번호를 지어내지 않는다.
    public static let safetyCardWithoutContactsKo =
        "기록은 그대로 저장됐어요. 지금 이야기할 곳이 필요하면 지역의 응급 번호로 연락할 수 있어요."

    public static let safetyCardWithoutContactsEn =
        "Your note was saved as written. If you need someone to talk to right now, you can call your local emergency number."

    public static func safetyCardWithoutContacts(_ language: JanjanLanguage) -> String {
        language == .english ? safetyCardWithoutContactsEn : safetyCardWithoutContactsKo
    }
}
