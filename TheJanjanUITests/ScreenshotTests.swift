import XCTest

/// 화면을 찍어 오는 테스트.
///
/// 개발 머신에 맥이 없어 시뮬레이터를 눈으로 볼 수 없다. 그래서 CI 의 macOS 러너가
/// 예시 기록을 심은 앱을 띄우고 화면마다 사진을 찍어 첨부로 남긴다.
/// 워크플로가 그 첨부를 꺼내 PNG 로 브랜치에 올리고, 그것을 받아 본다.
///
/// **무언가를 단정하지 않는다.** 이 파일이 하는 일은 걸어 다니며 찍는 것뿐이다.
/// 다만 화면이 안 뜨거나 탭이 없으면 찾기에서 실패하므로, 그 자체가 얕은 연기 테스트가 된다.
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["-JanjanSeedDemoData"]
        // 시뮬레이터에는 iCloud 계정도 entitlement 도 없다. 저장소 문제로 흔들리지 않게.
        app.launchEnvironment["JANJAN_DISABLE_CLOUDKIT"] = "1"
        app.launch()
    }

    /// **테스트는 하나뿐이다.** 나눠서 앱을 두 번 띄웠더니 두 번째 실행이
    /// "Failed to send signal 19" 로 걸려 25분을 멈춰 있었다(2026-08-26).
    /// 시뮬레이터에서 앱을 다시 띄우는 것이 불안정하므로 한 번 띄우고 다 돈다.
    func testCaptureEveryScreen() throws {
        // 탭 막대가 뜰 때까지 기다린다. 여기서 실패하면 앱이 안 뜬 것이다.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "탭 막대가 뜨지 않았습니다")

        capture("01-오늘")

        tap(tab: "약")
        capture("02-약")

        // 첫 약을 눌러 상세로. "선생님이 말씀하신 것" 카드가 여기 있다.
        let firstMedication = app.buttons.matching(identifier: "medicationRow").firstMatch
        if firstMedication.waitForExistence(timeout: 10) {
            firstMedication.tap()
            settle()
            capture("03-약-상세")
            back()
        }

        // 처방 기록. 다음 진료 D- 와 소진 예측이 여기서 살아난다.
        let prescription = app.buttons["처방 기록하기"]
        if prescription.waitForExistence(timeout: 10) {
            prescription.tap()
            settle()
            capture("08-처방-기록")
            dismissSheet()
        }

        // 약 추가 -> 직접 입력 폼.
        let add = app.buttons["약 추가"]
        if add.waitForExistence(timeout: 10) {
            add.tap()
            settle()
            capture("09-약-추가")

            let direct = app.buttons.matching(identifier: "directEntry").firstMatch
            if direct.waitForExistence(timeout: 5) {
                direct.tap()
                settle()
                capture("10-약-등록-폼")
            }
            dismissSheet()
        }

        tap(tab: "기록")
        capture("04-기록")

        // 2층을 펼친 모습도 남긴다. 접힌 채로는 무엇이 있는지 보이지 않는다.
        let expand = app.buttons["더 남기기"]
        if expand.waitForExistence(timeout: 5) {
            expand.tap()
            // 펼치는 애니메이션이 끝나기를 기다린다. 바로 찍으면 "접기" 와
            // "더 남기기" 가 겹친 채로 남는다(실제로 그렇게 찍혔다).
            Thread.sleep(forTimeInterval: 1.5)
            capture("05-기록-펼침")
        }

        tap(tab: "리포트")
        capture("06-리포트")

        // 설정은 오늘 탭 우상단 톱니에서 올라온다.
        tap(tab: "오늘")
        let settings = app.buttons["설정"]
        if settings.waitForExistence(timeout: 10) {
            settings.tap()
            settle()
            capture("07-설정")
        }
    }

    // MARK: - 조각

    private func tap(tab name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 15), "\(name) 탭을 찾지 못했습니다")
        button.tap()
        // 화면이 자리를 잡을 틈을 준다. 애니메이션 도중에 찍으면 흐릿하게 남는다.
        Thread.sleep(forTimeInterval: 1.2)
    }

    /// 화면이 자리를 잡을 틈. 애니메이션 도중에 찍으면 흐릿하게 남는다.
    private func settle() {
        Thread.sleep(forTimeInterval: 1.2)
    }

    /// 시트를 닫는다. "닫기" 가 없으면 아래로 밀어 내린다.
    private func dismissSheet() {
        let close = app.buttons["닫기"].firstMatch
        if close.waitForExistence(timeout: 3) {
            close.tap()
        } else {
            app.swipeDown()
        }
        settle()
    }

    private func back() {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists { backButton.tap() }
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
