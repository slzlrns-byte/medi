import Foundation
import JanjanCore

// 언어 선택의 앱 계층. 코어(JanjanLanguage)는 값만 알고, 어디에 저장하고
// 어떻게 읽는지는 여기서 정한다. 이 파일은 앱과 위젯 두 타깃에 들어간다.

extension JanjanLanguage {

    /// 설정의 언어 선택. 테마·서체처럼 UserDefaults 에 둔다.
    static let defaultsKey = "janjan.language"

    /// 지금 고른 언어.
    ///
    /// 위젯은 별도 프로세스라 앱의 standard defaults 가 안 보인다. 그래서
    /// 앱 그룹을 먼저 보고, (그룹이 없는 환경까지 대비해) standard 로 떨어진다.
    /// 앱이 값을 바꿀 때 두 곳에 같이 쓴다 — `store(_:)`.
    static var current: JanjanLanguage {
        let raw = UserDefaults(suiteName: Janjan.appGroupID)?.string(forKey: defaultsKey)
            ?? UserDefaults.standard.string(forKey: defaultsKey)
        return JanjanLanguage(rawValue: raw ?? "") ?? .standard
    }

    /// 선택을 저장한다. 위젯이 다음 갱신 때 같은 언어를 읽도록 그룹에도 쓴다.
    static func store(_ language: JanjanLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: defaultsKey)
        UserDefaults(suiteName: Janjan.appGroupID)?.set(language.rawValue, forKey: defaultsKey)
    }
}

/// 화면 문구를 두 언어로 한 자리에서 적는다: `t("아침", "Morning")`.
///
/// 이 저장소의 관례는 "한국어가 코드에 그대로 보인다" 이다. 키 파일로 빼면
/// 문구를 고칠 때마다 두 파일을 오가게 되고, 말투 규칙(존댓말·이모지 없음)을
/// 코드 리뷰에서 눈으로 지킬 수 없다. 그래서 번역을 원문 옆에 둔다.
func t(_ ko: String, _ en: String) -> String {
    JanjanLanguage.current == .english ? en : ko
}

/// 영어의 알 개수: "1 pill" / "0.5 pills". 한국어 "정" 은 셈이 없어 짝이 필요 없다.
func pillsEn(_ quantity: Decimal) -> String {
    "\(DecimalQuantity.display(quantity)) \(quantity == 1 ? "pill" : "pills")"
}
