import XCTest
@testable import JanjanCore

/// 자간·행간 규칙.
///
/// 값 자체보다 **방향**이 중요하다. 크기마다 손으로 적기 시작하면 화면마다 어긋나고,
/// 어긋난 것은 눈으로 보기 전까지 아무도 모른다.
final class TypographyTests: XCTestCase {

    // MARK: - 자간

    func testBigTextIsTightened() {
        // 한글은 큰 제목에서 자간이 벌어져 보인다.
        XCTAssertLessThan(JanjanTypography.tracking(forSize: 32), 0)
        XCTAssertLessThan(JanjanTypography.tracking(forSize: 24), 0)
    }

    func testSmallTextIsLoosened() {
        // 12pt 아래에서는 자소가 붙어 보이기 시작한다.
        XCTAssertGreaterThan(JanjanTypography.tracking(forSize: 11), 0)
        XCTAssertGreaterThan(JanjanTypography.tracking(forSize: 12), 0)
    }

    func testMidSizeIsLeftAlone() {
        XCTAssertEqual(JanjanTypography.tracking(forSize: 15), 0)
        XCTAssertEqual(JanjanTypography.tracking(forSize: 16), 0)
    }

    /// 크기가 커질수록 자간이 좁아져야 한다. 중간에 뒤집히면 어떤 크기에서 글자가
    /// 갑자기 벌어지는데, 그런 것은 화면을 보기 전까지 눈치채지 못한다.
    func testTrackingNeverGoesBackUpAsSizeGrows() {
        var previous = Double.greatestFiniteMagnitude
        for size in stride(from: 9.0, through: 48.0, by: 1.0) {
            let value = JanjanTypography.tracking(forSize: size)
            XCTAssertLessThanOrEqual(value, previous, "\(size)pt 에서 자간이 다시 벌어집니다")
            previous = value
        }
    }

    func testTrackingStaysReadable() {
        // 지나치게 좁히면 글자가 서로 먹는다.
        for size in stride(from: 9.0, through: 48.0, by: 1.0) {
            let value = JanjanTypography.tracking(forSize: size)
            XCTAssertGreaterThan(value, -1.0)
            XCTAssertLessThan(value, 0.5)
        }
    }

    // MARK: - 행간

    func testBodyBreathesMoreThanDisplay() {
        // 제목을 본문만큼 벌리면 한 덩어리로 안 읽히고 줄이 흩어진다.
        let size = 22.0
        XCTAssertGreaterThan(
            JanjanTypography.lineSpacing(forSize: size, role: .body),
            JanjanTypography.lineSpacing(forSize: size, role: .display)
        )
    }

    func testBodyLineSpacingIsGenerousEnoughForHangul() {
        // 15pt 본문에 5pt 이상은 붙어야 답답하지 않다.
        XCTAssertGreaterThanOrEqual(JanjanTypography.lineSpacing(forSize: 15, role: .body), 5)
        XCTAssertGreaterThanOrEqual(JanjanTypography.lineSpacing(forSize: 13, role: .body), 5)
    }

    func testLineSpacingGrowsWithSize() {
        for role in [JanjanTypography.Role.display, .body] {
            var previous = -1.0
            for size in stride(from: 11.0, through: 40.0, by: 1.0) {
                let value = JanjanTypography.lineSpacing(forSize: size, role: role)
                XCTAssertGreaterThanOrEqual(value, previous, "\(size)pt 에서 행간이 줄었습니다")
                previous = value
            }
        }
    }

    func testLineSpacingIsNeverNegative() {
        for size in stride(from: 9.0, through: 48.0, by: 1.0) {
            XCTAssertGreaterThanOrEqual(JanjanTypography.lineSpacing(forSize: size, role: .body), 0)
            XCTAssertGreaterThanOrEqual(JanjanTypography.lineSpacing(forSize: size, role: .display), 0)
        }
    }

    /// 행간이 글자 크기를 넘어서면 줄이 따로 놀아 한 문단으로 안 읽힌다.
    func testLineSpacingStaysBelowFontSize() {
        for size in stride(from: 11.0, through: 40.0, by: 1.0) {
            XCTAssertLessThan(JanjanTypography.lineSpacing(forSize: size, role: .body), size)
        }
    }
}
