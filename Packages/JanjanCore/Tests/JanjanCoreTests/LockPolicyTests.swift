import XCTest
@testable import JanjanCore

/// 앱 잠금의 유예 규칙. 잠기지 않아야 할 때 잠기는 것보다,
/// 잠겨야 할 때 안 잠기는 쪽이 더 큰 사고라서 경계값을 모두 적어 둔다.
final class LockPolicyTests: XCTestCase {

    /// 앱이 화면에서 사라진 시각.
    private let left = Fixed.date(2026, 8, 17, 21, 0)

    func testGraceZeroLocksTheMomentTheAppLeavesTheScreen() {
        XCTAssertEqual(LockPolicy.defaultGraceSeconds, 0)

        XCTAssertTrue(
            LockPolicy.shouldLock(now: left, lastBackgroundedAt: left, graceSeconds: 0)
        )
        XCTAssertTrue(
            LockPolicy.shouldLock(now: left.addingTimeInterval(1), lastBackgroundedAt: left, graceSeconds: 0)
        )
    }

    func testWithinGraceStaysOpenAndAfterGraceLocks() {
        // 1분 유예
        XCTAssertFalse(
            LockPolicy.shouldLock(now: left.addingTimeInterval(30), lastBackgroundedAt: left, graceSeconds: 60)
        )
        XCTAssertFalse(
            LockPolicy.shouldLock(now: left.addingTimeInterval(59), lastBackgroundedAt: left, graceSeconds: 60)
        )
        XCTAssertTrue(
            LockPolicy.shouldLock(now: left.addingTimeInterval(60), lastBackgroundedAt: left, graceSeconds: 60)
        )

        // 5분 유예
        XCTAssertFalse(
            LockPolicy.shouldLock(now: left.addingTimeInterval(299), lastBackgroundedAt: left, graceSeconds: 300)
        )
        XCTAssertTrue(
            LockPolicy.shouldLock(now: left.addingTimeInterval(301), lastBackgroundedAt: left, graceSeconds: 300)
        )
    }

    func testUnknownTimeOrBackwardClockLocks() {
        // 콜드 런치 — 나간 시각을 모른다.
        XCTAssertTrue(
            LockPolicy.shouldLock(now: left, lastBackgroundedAt: nil, graceSeconds: 300)
        )
        // 기기 시계를 뒤로 돌려 유예를 늘리는 것도 통하지 않는다.
        XCTAssertTrue(
            LockPolicy.shouldLock(now: left.addingTimeInterval(-600), lastBackgroundedAt: left, graceSeconds: 300)
        )
        // 어딘가에서 음수가 흘러들어와도 유예 없음처럼 다룬다.
        XCTAssertTrue(
            LockPolicy.shouldLock(now: left, lastBackgroundedAt: left, graceSeconds: -60)
        )
    }

    func testSettingsOptionsAndLabels() {
        XCTAssertEqual(LockPolicy.allowedGraceSeconds, [0, 60, 300])
        XCTAssertEqual(LockPolicy.graceLabelKo(forSeconds: 0), "바로")
        XCTAssertEqual(LockPolicy.graceLabelKo(forSeconds: 60), "1분 후")
        XCTAssertEqual(LockPolicy.graceLabelKo(forSeconds: 300), "5분 후")
    }
}
