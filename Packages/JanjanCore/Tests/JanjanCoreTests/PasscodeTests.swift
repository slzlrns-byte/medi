import XCTest
@testable import JanjanCore

/// 네 자리 잠금의 규칙.
///
/// 이 앱에는 서버도 계정도 없다. 잠긴 것을 풀어 줄 곳이 없으므로
/// "영영 잠기지 않는다" 가 이 파일에서 가장 중요한 성질이다.
final class PasscodeTests: XCTestCase {

    private let now = Fixed.date(2026, 8, 20, 21, 0)

    // MARK: - 모양

    func testFourDigitsIsValid() {
        XCTAssertEqual(Passcode.validate("0193"), .ok)
    }

    func testWrongLengthIsRejected() {
        XCTAssertEqual(Passcode.validate("019"), .wrongLength)
        XCTAssertEqual(Passcode.validate("01930"), .wrongLength)
        XCTAssertEqual(Passcode.validate(""), .wrongLength)
    }

    func testNonDigitsAreRejected() {
        XCTAssertEqual(Passcode.validate("01a3"), .notDigits)
        XCTAssertEqual(Passcode.validate("영일구삼"), .notDigits)
        // 전각 숫자와 한자 숫자는 isNumber 가 참이라 그냥 두면 새어 들어온다.
        XCTAssertEqual(Passcode.validate("０１９３"), .notDigits)
        XCTAssertEqual(Passcode.validate("一二三四"), .notDigits)
    }

    func testDigitCheckRunsBeforeLengthCheck() {
        // 글자가 섞였으면 길이보다 그 사실을 먼저 말해 주는 편이 고치기 쉽다.
        XCTAssertEqual(Passcode.validate("a"), .notDigits)
    }

    // MARK: - 쉬운 번호

    func testObviousPinsAreFlagged() {
        for pin in ["0000", "1111", "9999", "1234", "3456", "4321", "9876", "1212", "2626"] {
            XCTAssertTrue(Passcode.isEasilyGuessed(pin), "\(pin) 을 못 잡았습니다")
        }
    }

    func testOrdinaryPinsAreNotFlagged() {
        for pin in ["0193", "7412", "2059", "8003"] {
            XCTAssertFalse(Passcode.isEasilyGuessed(pin), "\(pin) 을 잘못 잡았습니다")
        }
    }

    func testEasyGuessIsAWarningNotABlock() {
        // 쉬운 번호도 '쓸 수 있는 모양' 이기는 하다. 막는 것이 아니라 알려만 준다.
        XCTAssertEqual(Passcode.validate("1234"), .ok)
    }

    func testEasyGuessMessageDoesNotScold() {
        let message = Passcode.easyGuessMessageKo
        XCTAssertFalse(message.contains("!"))
        for word in ["위험", "안 됩니다", "금지", "잘못"] {
            XCTAssertFalse(message.contains(word), "나무라는 말이 들어갔습니다: \(message)")
        }
    }

    // MARK: - 기다림

    func testFirstFewMistakesCostNothing() {
        for attempts in 0..<PasscodeThrottle.freeAttempts {
            XCTAssertEqual(PasscodeThrottle.delay(afterFailedAttempts: attempts), 0)
        }
    }

    func testDelayGrowsButNeverPastTheCap() {
        var previous: TimeInterval = 0
        for attempts in PasscodeThrottle.freeAttempts...40 {
            let delay = PasscodeThrottle.delay(afterFailedAttempts: attempts)
            XCTAssertGreaterThan(delay, 0)
            XCTAssertGreaterThanOrEqual(delay, previous, "기다림이 줄어들었습니다")
            XCTAssertLessThanOrEqual(delay, PasscodeThrottle.maximumDelay)
            previous = delay
        }
    }

    /// 이 앱에서 가장 위험한 실패는 사용자가 자기 기록에서 영영 잠겨 나가는 것이다.
    func testWaitingAlwaysEnds() {
        let attempts = 999
        let lastFailure = now
        let wait = PasscodeThrottle.delay(afterFailedAttempts: attempts)
        XCTAssertLessThanOrEqual(wait, PasscodeThrottle.maximumDelay)

        let afterWaiting = lastFailure.addingTimeInterval(PasscodeThrottle.maximumDelay + 1)
        XCTAssertEqual(
            PasscodeThrottle.remainingLockout(
                now: afterWaiting,
                lastFailureAt: lastFailure,
                failedAttempts: attempts
            ),
            0
        )
    }

    func testRemainingCountsDown() {
        let lastFailure = now
        let attempts = PasscodeThrottle.freeAttempts  // 60초

        XCTAssertEqual(
            PasscodeThrottle.remainingLockout(
                now: lastFailure.addingTimeInterval(20),
                lastFailureAt: lastFailure,
                failedAttempts: attempts
            ),
            40,
            accuracy: 0.001
        )
    }

    func testNoFailureYetMeansNoWait() {
        XCTAssertEqual(
            PasscodeThrottle.remainingLockout(now: now, lastFailureAt: nil, failedAttempts: 99),
            0
        )
    }

    func testBackwardsClockDoesNotSkipTheWait() {
        // 기기 시계를 뒤로 돌려 기다림을 건너뛰지 못하게 한다.
        let attempts = PasscodeThrottle.freeAttempts
        let remaining = PasscodeThrottle.remainingLockout(
            now: now.addingTimeInterval(-3600),
            lastFailureAt: now,
            failedAttempts: attempts
        )
        XCTAssertEqual(remaining, PasscodeThrottle.delay(afterFailedAttempts: attempts))
    }

    // MARK: - 문구

    func testWaitMessageRoundsUpAndStaysCalm() {
        XCTAssertNil(PasscodeThrottle.messageKo(forRemaining: 0))
        XCTAssertEqual(PasscodeThrottle.messageKo(forRemaining: 40), "40초 뒤에 다시 해 볼 수 있어요.")
        XCTAssertEqual(PasscodeThrottle.messageKo(forRemaining: 40.2), "41초 뒤에 다시 해 볼 수 있어요.")
        XCTAssertEqual(PasscodeThrottle.messageKo(forRemaining: 300), "5분 뒤에 다시 해 볼 수 있어요.")
        XCTAssertEqual(PasscodeThrottle.messageKo(forRemaining: 301), "6분 뒤에 다시 해 볼 수 있어요.")
    }

    func testWaitMessageDoesNotScold() {
        for seconds in [30.0, 120.0, 3600.0] {
            guard let message = PasscodeThrottle.messageKo(forRemaining: seconds) else {
                return XCTFail("문구가 없습니다")
            }
            XCTAssertFalse(message.contains("!"))
            for word in ["틀렸", "실패", "경고", "잘못"] {
                XCTAssertFalse(message.contains(word), "나무라는 말이 들어갔습니다: \(message)")
            }
        }
    }
}
