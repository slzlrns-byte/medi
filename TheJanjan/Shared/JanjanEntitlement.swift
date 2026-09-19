import Foundation
import JanjanCore

// Pro 권한의 그림자 값. 진짜 권한은 언제나 StoreKit 의 `currentEntitlements`
// 이고(ProStore), 여기 있는 것은 그것을 읽을 수 없는 곳에서 쓰는 사본이다.
//
// 읽는 곳이 둘이다.
//   · 알림 예약 - ProStore 를 들 수 없는 자리에서 되물음을 걸지 말지 정한다.
//   · 위젯 - 별도 프로세스라 앱의 standard defaults 가 아예 안 보인다.
//
// 그래서 JanjanPrivacy·JanjanLanguage 와 같은 방식으로 앱 그룹을 먼저 보고
// 없으면 standard 로 떨어진다. **잠금의 최종 판단에는 쓰지 않는다** - 화면은
// ProStore.isPro 를 보고, 이 값은 프로세스 밖에서 참고하는 힌트다.

enum JanjanEntitlement {

    /// 예전 이름(ProStore.cachedProKey)과 같은 키를 쓴다. 이미 깔린 기기에서
    /// 값이 이어지도록 문자열을 바꾸지 않는다.
    static let proKey = "janjan.pro.cached"

    static var isPro: Bool {
        UserDefaults(suiteName: Janjan.appGroupID)?.bool(forKey: proKey)
            ?? UserDefaults.standard.bool(forKey: proKey)
    }

    /// 권한이 바뀔 때마다 두 곳에 같이 쓴다. 한쪽만 쓰면 위젯이 옛 값을 본다.
    static func store(_ isPro: Bool) {
        UserDefaults.standard.set(isPro, forKey: proKey)
        UserDefaults(suiteName: Janjan.appGroupID)?.set(isPro, forKey: proKey)
    }
}
