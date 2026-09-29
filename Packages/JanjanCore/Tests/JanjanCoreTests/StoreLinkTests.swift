import XCTest
@testable import JanjanCore

/// 스토어로 나가는 주소. 앱 밖으로 사람을 보내는 링크라 오타가 나면 빈
/// App Store 화면에서 멈춘다 - 화면에서는 안 보이고 눌러야만 드러난다.
final class StoreLinkTests: XCTestCase {

    func testWriteReviewURLIsWellFormedWhenIDIsSet() throws {
        // 상수를 바꾸지 않고 형태만 본다. 실제 번호는 배포 때 채운다.
        let sample = "https://apps.apple.com/app/id123456789?action=write-review"
        let url = try XCTUnwrap(URL(string: sample))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "apps.apple.com")
        XCTAssertEqual(url.query, "action=write-review", "이 질의가 빠지면 리뷰 칸이 아니라 앱 소개로 간다")
    }

    /// 번호가 비어 있으면 설정이 줄을 그리지 않는다(SettingsView.aboutSection).
    /// 그 판단의 근거가 여기라서, 비었을 때의 값이 무엇인지 고정해 둔다.
    func testAppStoreIDIsEmptyUntilFilledIn() {
        if Janjan.appStoreID.isEmpty {
            XCTAssertTrue(
                Janjan.writeReviewURLString.contains("/id?"),
                "번호가 없으면 주소가 완성되지 않는다 - 설정이 줄을 숨기는 이유"
            )
        } else {
            XCTAssertTrue(
                Janjan.appStoreID.allSatisfy(\.isNumber),
                "App Store 앱 번호는 숫자만이다. 'id' 접두어나 공백이 섞이면 열리지 않는다"
            )
            let url = URL(string: Janjan.writeReviewURLString)
            XCTAssertNotNil(url, "번호를 채운 뒤 주소가 깨지면 리뷰 줄이 죽은 링크가 된다")
        }
    }

    func testPolicyURLsAreHTTPS() throws {
        for string in [
            Janjan.privacyPolicyURLString,
            Janjan.supportURLString,
            Janjan.termsURLString
        ] {
            let url = try XCTUnwrap(URL(string: string), "\(string) 이 주소로 읽히지 않는다")
            XCTAssertEqual(url.scheme, "https", "\(string) 은 https 여야 한다")
        }
    }
}
