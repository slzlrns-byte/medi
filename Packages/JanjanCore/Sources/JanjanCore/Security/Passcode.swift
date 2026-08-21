import Foundation

/// 앱 잠금 비밀번호(네 자리)의 규칙.
///
/// 저장·검증은 앱 계층(`PasscodeStore`)이 키체인으로 하고, **판단만** 여기 있다.
/// 시뮬레이터도 키체인도 필요 없는 순수 함수라 `swift test` 로 그대로 잠근다.
public enum Passcode {

    /// 네 자리로 고정한다. 길이를 고를 수 있게 하면 "몇 자리로 했더라" 가 하나 더 늘어난다.
    public static let length = 4

    public enum Validation: Hashable, Sendable {
        case ok
        /// 자릿수가 모자라거나 넘친다.
        case wrongLength
        /// 숫자가 아닌 글자가 섞였다.
        case notDigits

        public var messageKo: String? {
            switch self {
            case .ok: return nil
            case .wrongLength: return "네 자리를 눌러 주세요."
            case .notDigits: return "숫자만 쓸 수 있어요."
            }
        }
    }

    public static func validate(_ text: String) -> Validation {
        guard text.allSatisfy(\.isASCIIDigit) else { return .notDigits }
        guard text.count == length else { return .wrongLength }
        return .ok
    }

    /// 너무 쉬운 번호인가.
    ///
    /// **막지 않는다.** 한 번 알려 주고 그래도 쓰겠다면 쓰게 둔다.
    /// 이 잠금이 막으려는 것은 곁에 있는 사람이 무심코 열어 보는 일이지
    /// 작정하고 만 번을 눌러 보는 사람이 아니다. 여기서 사용자와 싸우면
    /// 잠금을 아예 꺼 버리는 쪽으로 간다.
    public static func isEasilyGuessed(_ pin: String) -> Bool {
        let digits = pin.compactMap(\.wholeNumberValue)
        guard digits.count == length else { return false }

        // 0000, 1111 …
        if Set(digits).count == 1 { return true }

        // 1234, 2345 … 그리고 4321, 9876 …
        let ascending = zip(digits, digits.dropFirst()).allSatisfy { $1 - $0 == 1 }
        let descending = zip(digits, digits.dropFirst()).allSatisfy { $0 - $1 == 1 }
        if ascending || descending { return true }

        // 1212, 2626 처럼 두 자리가 되풀이되는 것.
        if digits[0] == digits[2] && digits[1] == digits[3] { return true }

        return false
    }

    public static let easyGuessMessageKo =
        "쉽게 짐작할 수 있는 번호예요. 그대로 쓰셔도 되지만 다른 번호를 권해요."
}

private extension Character {
    /// `isNumber` 는 한자 숫자나 위 첨자까지 참이라 키패드 입력 검사로는 헐겁다.
    var isASCIIDigit: Bool { isASCII && isNumber }
}

/// 틀렸을 때 얼마나 기다리게 할지.
///
/// **영영 잠그지 않는다.** 이 앱에는 서버도 계정도 없어서 잠긴 것을 풀어 줄 곳이 없다.
/// 기다림은 길어져도 반드시 끝나고, 기기 인증으로 되찾는 길은 그동안에도 열려 있다.
public enum PasscodeThrottle {

    /// 이 횟수까지는 기다림 없이 다시 눌러 볼 수 있다.
    /// 네 자리는 손가락이 미끄러지기 쉬워서 처음 몇 번은 벌하지 않는다.
    public static let freeAttempts = 5

    /// 아무리 틀려도 이보다 오래 기다리지는 않는다.
    public static let maximumDelay: TimeInterval = 3600

    /// 지금까지 틀린 횟수에 따른 기다림(초).
    public static func delay(afterFailedAttempts attempts: Int) -> TimeInterval {
        switch attempts {
        case ..<freeAttempts: return 0
        case freeAttempts, freeAttempts + 1: return 60
        case freeAttempts + 2: return 300
        case freeAttempts + 3: return 900
        default: return maximumDelay
        }
    }

    /// 지금 몇 초를 더 기다려야 하는가. 0 이면 바로 눌러 볼 수 있다.
    ///
    /// 기기 시계가 거꾸로 갔으면 기다림을 처음부터 다시 잰다.
    /// 그러지 않으면 시계를 돌려 기다림을 건너뛸 수 있다(`LockPolicy` 와 같은 태도).
    public static func remainingLockout(
        now: Date,
        lastFailureAt: Date?,
        failedAttempts: Int
    ) -> TimeInterval {
        guard let lastFailureAt else { return 0 }
        let wait = delay(afterFailedAttempts: failedAttempts)
        guard wait > 0 else { return 0 }

        let elapsed = now.timeIntervalSince(lastFailureAt)
        guard elapsed >= 0 else { return wait }
        return max(0, wait - elapsed)
    }

    /// 기다리는 동안 보여 줄 한 문장. 나무라지 않고 언제 다시 되는지만 말한다.
    public static func messageKo(forRemaining seconds: TimeInterval) -> String? {
        guard seconds > 0 else { return nil }
        if seconds < 60 {
            return "\(Int(seconds.rounded(.up)))초 뒤에 다시 해 볼 수 있어요."
        }
        let minutes = Int((seconds / 60).rounded(.up))
        return "\(minutes)분 뒤에 다시 해 볼 수 있어요."
    }
}
