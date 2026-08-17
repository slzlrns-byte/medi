import Foundation

/// 앱 잠금을 "다시 걸어야 하는지" 판단하는 규칙.
///
/// LocalAuthentication 과 화면은 앱 계층(`AppLockManager`)에 두고, 판단만 여기로 끌어낸다.
/// 시뮬레이터도 생체인식도 필요 없는 순수 함수라 `swift test` 로 그대로 잠글 수 있다.
///
/// 판단이 서지 않는 경우는 **잠그는 쪽**으로 기운다. 기록이 열린 채로 남는 사고보다
/// 한 번 더 묻는 번거로움이 낫다.
public struct LockPolicy: Hashable, Sendable {

    /// 설정에서 고를 수 있는 유예 시간(초) — 바로 / 1분 후 / 5분 후.
    public static let allowedGraceSeconds: [Int] = [0, 60, 300]

    /// 기본값은 유예 없음. 앱이 화면에서 사라지면 곧바로 잠근다.
    public static let defaultGraceSeconds: Int = 0

    /// 잠금을 걸어야 하는가.
    ///
    /// - Parameters:
    ///   - now: 판단하는 시각.
    ///   - lastBackgroundedAt: 앱이 마지막으로 화면에서 사라진 시각. 모르면 `nil`.
    ///   - graceSeconds: 이 시간 안에 돌아오면 잠그지 않는다. `0` 이면 항상 잠근다.
    /// - Returns: 잠가야 하면 `true`.
    ///
    /// 나간 시각을 모르거나(콜드 런치), 기기 시계가 거꾸로 간 경우에는 잠근다.
    /// 뒤엣것이 없으면 시계를 돌려 유예를 늘릴 수 있다.
    public static func shouldLock(
        now: Date,
        lastBackgroundedAt: Date?,
        graceSeconds: TimeInterval
    ) -> Bool {
        guard let lastBackgroundedAt else { return true }
        let elapsed = now.timeIntervalSince(lastBackgroundedAt)
        guard elapsed >= 0 else { return true }
        return elapsed >= max(0, graceSeconds)
    }

    /// 설정 화면의 선택지 라벨. 존댓말, 이모지 없음.
    public static func graceLabelKo(forSeconds seconds: Int) -> String {
        if seconds <= 0 { return "바로" }
        if seconds < 60 { return "\(seconds)초 후" }
        return "\(seconds / 60)분 후"
    }
}
