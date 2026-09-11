import Foundation
import JanjanCore

// "약 이름 가리기"(Pro)의 저장 계층. 코어는 값만 알고, 어디에 저장하고
// 어떻게 읽는지는 여기서 정한다. 이 파일은 앱과 위젯 두 타깃에 들어간다.
//
// 언어 선택(JanjanLanguage.current/store)과 같은 자리를 쓴다 — 위젯은 별도
// 프로세스라 앱의 standard defaults 가 안 보이므로 앱 그룹을 먼저 보고,
// 없으면 standard 로 떨어진다.

enum JanjanPrivacy {

    /// 켜져 있는지 여부. 테마·서체·언어처럼 UserDefaults 에 둔다.
    static let hideNamesKey = "janjan.hideNames"

    /// 지금 켜져 있는지.
    ///
    /// 앱이 값을 바꿀 때 두 곳에 같이 쓴다 — `store(_:)`.
    static var hidesNames: Bool {
        UserDefaults(suiteName: Janjan.appGroupID)?.bool(forKey: hideNamesKey)
            ?? UserDefaults.standard.bool(forKey: hideNamesKey)
    }

    /// 선택을 저장한다. 위젯이 다음 갱신 때 같은 값을 읽도록 그룹에도 쓴다.
    static func store(_ hides: Bool) {
        UserDefaults.standard.set(hides, forKey: hideNamesKey)
        UserDefaults(suiteName: Janjan.appGroupID)?.set(hides, forKey: hideNamesKey)
    }
}
