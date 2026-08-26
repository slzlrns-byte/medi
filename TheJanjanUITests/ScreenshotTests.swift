import XCTest

/// 화면을 찍어 오는 테스트.
///
/// 개발 머신에 맥이 없어 시뮬레이터를 눈으로 볼 수 없다. 그래서 CI 의 macOS 러너가
/// 예시 기록을 심은 앱을 띄우고 화면마다 사진을 찍어 첨부로 남긴다.
/// 워크플로가 그 첨부를 꺼내 PNG 로 브랜치에 올리고, 그것을 받아 본다.
///
/// **무언가를 단정하지 않는다.** 이 파일이 하는 일은 걸어 다니며 찍는 것뿐이다.
/// 다만 걸어가려는 곳에 실제로 도착했는지는 확인한다 — 아래 주석 참고.
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
    ///
    /// **순서는 번호순이 아니다.** 시트를 여는 화면을 마지막에 모아 뒀다.
    /// 시트가 안 닫히면 그 뒤의 탭 누르기가 전부 시트에 맞기 때문에, 앞에 두면
    /// 뒤가 통째로 오염된다. 실제로 그랬다 — 안 닫힌 약 등록 폼 위에서 탭을 눌러
    /// 같은 사진을 '기록'과 '리포트' 라는 이름으로 두 장 찍어 놨다(2026-08-26).
    /// 이제 시트는 맨 뒤에 있어서, 못 닫아도 잃는 것이 없다.
    func testCaptureEveryScreen() throws {
        // 탭 막대가 뜰 때까지 기다린다. 여기서 실패하면 앱이 안 뜬 것이다.
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 30), "탭 막대가 뜨지 않았습니다")

        // ── 탭으로 갈 수 있는 화면들 ─────────────────────────────────
        capture("01-오늘")

        // 설정은 오늘 탭 우상단 톱니에서 올라온다.
        let settings = app.buttons["설정"]
        if settings.waitForExistence(timeout: 10) {
            settings.tap()
            settle()
            capture("07-설정")
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

        tap(tab: "약")
        capture("02-약")

        // 첫 약을 눌러 상세로. "선생님이 말씀하신 것" 카드가 여기 있다.
        // 시트가 아니라 밀어 넣기라 뒤로 나오면 그만이다.
        let firstMedication = app.buttons.matching(identifier: "medicationRow").firstMatch
        if firstMedication.waitForExistence(timeout: 10) {
            firstMedication.tap()
            settle()
            waitUntilStill(app.navigationBars.firstMatch)
            capture("03-약-상세")
            back()
        }

        // ── 여기서부터 시트 ──────────────────────────────────────────
        // 못 닫아도 뒤가 없으므로 잃는 것이 없다.

        // 처방 기록. 다음 진료 D- 와 소진 예측이 여기서 살아난다.
        let prescription = app.buttons["처방 기록하기"]
        if prescription.waitForExistence(timeout: 10) {
            prescription.tap()
            settle()
            capture("08-처방-기록")
            dismissSheet()
        }

        // 약 추가 -> 직접 입력 폼. 이 줄이 마지막이다.
        let add = app.buttons["약 추가"]
        if add.waitForExistence(timeout: 10) {
            add.tap()
            settle()
            capture("09-약-추가")

            let direct = app.buttons.matching(identifier: "directEntry").firstMatch
            if direct.waitForExistence(timeout: 5) {
                direct.tap()
                settle()
                // 폼 내용이 자리를 잡을 때까지 기다린다. 카드 안의 글이
                // 화면 안에 들어와 멈춰야 다 밀려 들어온 것이다.
                waitUntilStill(app.staticTexts["어떻게 먹는 약인가요"])
                capture("10-약-등록-폼")
            }
        }
    }

    // MARK: - 조각

    /// 탭을 누르고 **정말 그 탭으로 갔는지 확인한다.**
    ///
    /// 찾기만 해서는 모자란다. 시트에 덮여 있어도 탭 막대는 계층에 그대로 있어서
    /// waitForExistence 는 통과하고, tap() 은 시트에 맞는다. 그러면 엉뚱한 화면이
    /// '기록' 이라는 이름으로 조용히 찍혀 나온다 — 사진을 받아 보기 전에는 모른다.
    private func tap(tab name: String,
                     file: StaticString = #filePath,
                     line: UInt = #line) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 15),
                      "\(name) 탭을 찾지 못했습니다", file: file, line: line)
        XCTAssertTrue(button.isHittable,
                      "\(name) 탭이 무언가에 덮여 있습니다", file: file, line: line)
        button.tap()
        // 화면이 자리를 잡을 틈을 준다. 애니메이션 도중에 찍으면 흐릿하게 남는다.
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertTrue(button.isSelected,
                      "\(name) 탭을 눌렀는데 선택되지 않았습니다", file: file, line: line)
    }

    /// 화면이 자리를 잡을 틈. 애니메이션 도중에 찍으면 흐릿하게 남는다.
    private func settle() {
        Thread.sleep(forTimeInterval: 1.2)
    }

    /// 화면이 **정말** 멈췄는지 본다.
    ///
    /// 1.2초를 자고 찍었는데도 밀어 넣기가 끝나지 않은 사진이 나왔다 —
    /// 제목 막대는 제자리인데 내용만 왼쪽으로 밀려 잘려 있었다(2026-08-26).
    /// 시간을 재는 대신 자리를 본다. 같은 자리에 두 번 연속으로 있고 화면 안에
    /// 들어와 있으면 멈춘 것이다. 못 멈추면 그냥 넘어간다 - 여기서 실패로
    /// 끊는 것보다 흐릿하더라도 한 장 남기는 편이 낫다.
    private func waitUntilStill(_ element: XCUIElement, timeout: TimeInterval = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        var previous = CGRect.null

        while Date() < deadline {
            guard element.exists else {
                Thread.sleep(forTimeInterval: 0.3)
                continue
            }
            let current = element.frame
            if current == previous && current.minX >= 0 { return }
            previous = current
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    /// 탭 막대를 누를 수 있으면 시트가 없는 것이다.
    /// 시트가 떠 있는지를 직접 묻는 것보다 이 편이 정확하다 — 우리가 실제로
    /// 알고 싶은 것이 "다음 탭을 누를 수 있는가" 이기 때문이다.
    private var isTabBarReachable: Bool {
        app.tabBars.firstMatch.isHittable
    }

    /// 시트를 닫고, **정말 닫혔는지 확인한다.**
    ///
    /// "닫기" 는 시트 뿌리에만 있다. 시트 안에서 다음 화면으로 밀고 들어가 있으면
    /// (약 추가 -> 직접 입력) 닫기가 없어서, 예전에는 swipeDown 으로 떨어졌다.
    /// 그런데 폼 위에서의 swipeDown 은 시트를 닫는 대신 내용만 스크롤한다.
    /// 그래서 먼저 뿌리로 나온 다음 닫는다.
    private func dismissSheet(file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<4 {
            let close = app.buttons["닫기"].firstMatch
            let backButton = app.navigationBars.buttons.element(boundBy: 0)

            if close.exists {
                close.tap()
            } else if backButton.exists {
                // 시트 안쪽 화면이다. 뿌리로 나와야 닫기가 나온다.
                backButton.tap()
            } else {
                app.swipeDown()
            }

            settle()
            if isTabBarReachable { return }
        }
        XCTFail("시트가 닫히지 않았습니다", file: file, line: line)
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
