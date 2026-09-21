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

    /// 사용자가 켜 두었는지. **적용 여부가 아니다** — 그건 `hidesNames` 다.
    ///
    /// 앱이 값을 바꿀 때 두 곳에 같이 쓴다 — `store(_:)`.
    static var isOn: Bool {
        UserDefaults(suiteName: Janjan.appGroupID)?.bool(forKey: hideNamesKey)
            ?? UserDefaults.standard.bool(forKey: hideNamesKey)
    }

    /// 지금 실제로 가리는 중인지.
    ///
    /// **Pro 가 아니면 켜져 있어도 아무 일도 하지 않는다.** 화면 여러 곳의
    /// 주석이 이미 그렇게 적혀 있었는데 정작 코드에는 그 조건이 없었다
    /// (QA 2026-09-21) — 페이월이 파는 항목이라, 어떤 경로로든 무료에서
    /// 스위치가 켜지면 그대로 적용됐다. 워치 스냅샷만 혼자 `isPro &&` 를
    /// 걸고 있었고, 이제 그 판단이 여기 한 곳으로 모인다.
    static var hidesNames: Bool {
        isOn && JanjanEntitlement.isPro
    }

    /// 선택을 저장한다. 위젯이 다음 갱신 때 같은 값을 읽도록 그룹에도 쓴다.
    static func store(_ hides: Bool) {
        UserDefaults.standard.set(hides, forKey: hideNamesKey)
        UserDefaults(suiteName: Janjan.appGroupID)?.set(hides, forKey: hideNamesKey)
    }
}
