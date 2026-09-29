import Foundation

/// 앱의 표시 언어. 시스템 언어를 따르지 않고 설정에서 고른다 (2026-09-10 결정).
///
/// 시스템을 따르지 않는 이유: 한국어 기기에서 영어로 쓰고 싶은 사람과
/// 영어 기기에서 한국어로 쓰고 싶은 사람이 둘 다 실제로 있다(재외 교포,
/// 한국에 사는 외국인). 테마·서체와 같은 자리에서 고르게 한다.
///
/// 코어는 이 값을 **인자로만** 받는다 — 어느 언어인지는 앱 계층이 정해서
/// 넘기고, 코어는 순수하게 두 벌의 글자를 들고만 있다.
public enum JanjanLanguage: String, Sendable, CaseIterable {
    case korean = "ko"
    case english = "en"

    /// 선택을 모르는 곳(테스트·기본값)이 쓰는 값. 한국어가 이 앱의 모어다.
    public static let standard: JanjanLanguage = .korean

    /// 언어 선택 화면에서는 각 언어를 그 언어로 적는다 —
    /// 영어를 몰라 한국어로 바꾸려는 사람이 "Korean" 을 읽게 하면 안 되고,
    /// 그 반대도 마찬가지다.
    public var labelNative: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "English"
        }
    }

    /// DatePicker 등 시스템 부품이 따라갈 로케일.
    public var localeIdentifier: String {
        switch self {
        case .korean: return "ko_KR"
        case .english: return "en_US"
        }
    }
}
