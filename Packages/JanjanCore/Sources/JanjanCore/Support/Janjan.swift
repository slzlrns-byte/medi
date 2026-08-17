import Foundation

/// 앱 전체가 공유하는 상수. 문구는 존댓말, 이모지 없음, 한 문장에 한 정보.
public enum Janjan {

    public static let appNameKo = "더잔잔"
    public static let appNameEn = "The Janjan"
    public static let sloganKo = "더 잔잔한 하루를 위해"

    /// iCloud 컨테이너. entitlements 파일과 반드시 같아야 한다.
    public static let cloudKitContainerID = "iCloud.com.thejanjan.app"

    public static let appBundleID = "com.thejanjan.app"
    public static let watchBundleID = "com.thejanjan.app.watchkitapp"

    /// 정책 페이지. 원본은 저장소의 `docs/site/` 이고 GitHub Pages 로 낸다.
    /// App Store Connect 의 URL 칸과 앱 설정 화면이 같은 주소를 쓴다.
    public static let privacyPolicyURLString = "https://slzlrns-byte.github.io/medi/site/privacy.html"
    public static let supportURLString = "https://slzlrns-byte.github.io/medi/site/support.html"
    public static let termsURLString = "https://slzlrns-byte.github.io/medi/site/terms.html"

    /// 앱 어디에도 진단·조언을 쓰지 않는다는 약속을 문장으로 고정해 둔다.
    public static let medicalDisclaimerKo =
        "이 앱은 의료 조언이 아닙니다. 복용 변경은 담당 의사와 상의해 주세요."

    /// 위기 상담 연락처. 안전 카드와 설정 화면에서 같은 값을 쓴다.
    public struct CrisisContact: Hashable, Sendable, Identifiable {
        public let id: String
        public let titleKo: String
        public let subtitleKo: String
        public let number: String

        public init(id: String, titleKo: String, subtitleKo: String, number: String) {
            self.id = id
            self.titleKo = titleKo
            self.subtitleKo = subtitleKo
            self.number = number
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
            number: "109"
        ),
        CrisisContact(
            id: "mental_health_crisis",
            titleKo: "정신건강위기상담",
            subtitleKo: "24시간 언제든",
            number: "1577-0199"
        )
    ]

    /// 안전 카드에 쓰는 문구. 경고도 진단도 아니고, 연락처를 조용히 내미는 한 문장.
    public static let safetyCardMessageKo =
        "기록은 그대로 저장됐어요. 지금 이야기할 곳이 필요하면 여기로 연락할 수 있어요."
}
