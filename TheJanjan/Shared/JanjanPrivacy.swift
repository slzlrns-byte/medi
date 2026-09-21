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
    /// **`bool(forKey:)` 로는 떨어질 수 없다**(QA 2026-09-21). 없는 키에도
    /// `false` 를 돌려주므로 `??` 는 그룹이 통째로 없을 때만 걸린다. 그룹은
    /// 있는데 그 안에 아직 값을 안 쓴 기기(앱 그룹 쓰기를 넣기 전에 스위치를
    /// 켜 둔 사람)에서는 켜 둔 값이 조용히 꺼진 것으로 읽혔다 - 목록·위젯·
    /// 잠금화면의 약 이름이 드러난다. 키가 있는지를 먼저 묻는다.
    static var isOn: Bool {
        if let group = UserDefaults(suiteName: Janjan.appGroupID),
           let stored = group.object(forKey: hideNamesKey) as? Bool {
            return stored
        }
        return UserDefaults.standard.bool(forKey: hideNamesKey)
    }

    /// 지금 실제로 가리는 중인지.
    ///
    /// **켜 두었으면 구독이 끝나도 계속 가린다.** 한때 `JanjanEntitlement.isPro`
    /// 를 곱했다가 되돌렸다(QA 2026-09-21) — 구독이 끊긴 다음 날 목록·위젯·
    /// **잠금화면 알림 본문**의 약 이름이 한꺼번에 드러났다. 정신과 약 이름을
    /// 남이 보지 못하게 하려고 켠 스위치이므로, 돈을 안 낸다고 회수할 것이
    /// 아니다. `JanjanEntitlement` 도 "잠금의 최종 판단에는 쓰지 않는다" 고
    /// 스스로 적어 두었다.
    ///
    /// 파는 것은 **새로 켜는 일**이고, 그 문은 설정 화면의 `.proGated` 가
    /// 지킨다. 무료 사용자는 스위치를 켤 수 없다.
    static var hidesNames: Bool { isOn }

    /// 선택을 저장한다. 위젯이 다음 갱신 때 같은 값을 읽도록 그룹에도 쓴다.
    static func store(_ hides: Bool) {
        UserDefaults.standard.set(hides, forKey: hideNamesKey)
        UserDefaults(suiteName: Janjan.appGroupID)?.set(hides, forKey: hideNamesKey)
    }
}
