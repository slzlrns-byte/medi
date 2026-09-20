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
        // Pro 화면(전후 보기 등)도 찍는다. 디버그 백도어라 출시 빌드에는 없는 스위치다.
        // 스토어 제출용 사진도 어차피 Pro 가 켜진 모습이 맞다.
        app.launchEnvironment["JANJAN_FORCE_PRO"] = "1"
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

        scrollToBottom()
        capture("01b-오늘-바닥")
        scrollToTop()

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

            // 펼친 아래쪽도 본다. 기운·불안의 1~5 줄이 여기 있는데, 한 장에는
            // 안 들어와서 넘치는지 아닌지를 확인할 수가 없었다.
            app.swipeUp()
            app.swipeUp()
            settle()
            capture("05b-기록-아래")
        }

        tap(tab: "진료 준비")
        capture("06-리포트")

        // 바닥까지 내려 본다. 탭 막대는 떠 있고 내용은 그 아래로 지나가므로,
        // 마지막 카드가 막대에 갇히지 않고 위로 올라오는지 눈으로 봐야 안다.
        // 여기가 화면 중 가장 길다.
        scrollToBottom()
        capture("06b-리포트-바닥")

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
        let prescription = app.buttons["진료 기록하기"]
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

                // 요일 일곱 개는 한 장에 안 들어온다. 화면 밖에 있으면 한 줄에
                // 고르게 들어갔는지 볼 수가 없어서 아래로 내려 한 장 더 찍는다.
                // 기록 탭에서 05b 를 넣은 것과 같은 이유다.
                app.swipeUp()
                app.swipeUp()
                settle()
                capture("10b-약-등록-폼-아래")
            }
            // 여기서는 못 닫아도 테스트를 죽이지 않는다. 이 뒤에 남은 것은
            // 한 장뿐이고, 그 한 장을 건너뛰는 것보다 런 전체가 빨갛게 끝나는
            // 쪽이 더 헷갈린다 - 실제로 폼 닫기가 한 박자 늦어 마지막 장만
            // 남기고 통째로 실패한 적이 있다(2026-09-10, 런 21).
            _ = tryDismissSheet()
        }

        // 기록 없이 지나간 시간대를 하나씩 답하는 시트. 데모 데이터가 어제·그제
        // 아침을 비워 두므로 "이틀 연속" 이 두 줄로 따로 보이는지 여기서 확인한다.
        if isTabBarReachable {
            tap(tab: "오늘")
            scrollToTop()
            let review = app.buttons["살펴보기"].firstMatch
            if review.waitForExistence(timeout: 5) {
                review.tap()
                settle()
                capture("15-지나간-시간대")
                _ = tryDismissSheet()
            }
        }

        // 약 상세의 "다시 세기". 센 개수까지 적어야 비교 문장과 미기록 목록이
        // 같이 나온다 - 데모 데이터 기준으로 기록상 잔여와 같은 17을 적는다.
        if isTabBarReachable {
            tap(tab: "약")
            let row = app.buttons.matching(identifier: "medicationRow").firstMatch
            if row.waitForExistence(timeout: 10) {
                row.tap()
                settle()
                let recount = app.buttons["다시 세기"].firstMatch
                if recount.waitForExistence(timeout: 5) {
                    recount.tap()
                    settle()
                    let field = app.textFields.firstMatch
                    if field.waitForExistence(timeout: 5) {
                        field.tap()
                        field.typeText("17")
                        settle()
                        // 숫자패드가 미기록 목록을 가리므로 한 번 밀어 올려 둔다.
                        app.swipeUp()
                        settle()
                    }
                    capture("16-다시-세기")
                    _ = tryDismissSheet()
                }
            }
        }

        // 용량 변경 전후 비교 시트(Pro). 데모 데이터에 9일 전 5mg→10mg 변경이
        // 있어 전 2주·후 2주가 실데이터로 채워진다.
        if isTabBarReachable {
            tap(tab: "약")
            // **앞 단계(다시 세기)가 약 상세에 서 있는 채로 끝난다.** 탭을 다시
            // 눌러도 SwiftUI 는 뿌리로 돌려보내지 않으므로, 목록 대신 상세가
            // 그대로 있고 medicationRow 를 영영 못 찾는다 - 09-19 · 09-20 두
            // 세트에서 넓은 기기의 이 한 장만 비어 있던 이유다(좁은 기기는
            // 시트를 닫느라 쓸어내린 것이 뒤로 가기로 먹혀 우연히 넘어갔다).
            // 목록이 보일 때까지 뒤로 나온다.
            var backs = 0
            while !app.buttons.matching(identifier: "medicationRow").firstMatch
                .waitForExistence(timeout: 2), backs < 3 {
                back()
                backs += 1
            }

            // **첫 줄을 잡으면 안 된다.** 용량 변경이 달린 약은 에스시탈로프람
            // 하나인데(DemoSeed.seedDoseChanges), 넓은 기기에서는 첫 줄이
            // 쿠에티아핀이라 "약 변경 보기" 가 아예 없는 화면에 들어가 있었다.
            // 좁은 기기는 첫 줄이 달라 우연히 맞았고, 그래서 한쪽에만 구멍이
            // 났다 - 두 세트를 이것으로 잃었다. 이름으로 찾는다.
            let rows = app.buttons.matching(identifier: "medicationRow")
            var row = rows.firstMatch
            for index in 0..<rows.count where rows.element(boundBy: index)
                .label.contains("에스시탈로프람") {
                row = rows.element(boundBy: index)
                break
            }
            if row.waitForExistence(timeout: 10) {
                row.tap()
                settle()
                let compare = app.buttons["약 변경 보기"].firstMatch
                // 용량 변경 카드는 화면 아래쪽이다. 한 번만 밀면 기기 높이에
                // 따라 지나치거나 못 미친다 — 09-19 세트에서 넓은 기기의
                // 이 한 장만 비어 있었다. 보일 때까지 조금씩 민다.
                var swipes = 0
                while !compare.waitForExistence(timeout: 2), swipes < 5 {
                    app.swipeUp()
                    settle()
                    swipes += 1
                }
                if compare.waitForExistence(timeout: 5) {
                    compare.tap()
                    settle()
                    capture("20-용량변경-전후")
                    _ = tryDismissSheet()
                }
            }
        }

        // 오늘의 시간대 타일 본문을 누르면 그 시간대의 약 목록 시트가 열린다.
        // 이것도 시트라 맨 뒤에 있다.
        if isTabBarReachable {
            tap(tab: "오늘")
            let morning = app.staticTexts["아침"].firstMatch
            if morning.waitForExistence(timeout: 10) {
                morning.tap()
                settle()
                capture("01c-아침-시트")
            }
        }

        capturePaywall()

        assertRequiredCaptures()
    }

    /// 구독 화면. **맨 마지막에 한다** - 앱을 다시 띄우므로 앞 단계가 만들어
    /// 둔 화면 상태가 사라진다.
    ///
    /// 두 가지를 바꿔 띄운다.
    ///   · `JANJAN_FORCE_PRO` 를 끈다. 켜 두면 페이월이 열리자마자 스스로
    ///     닫힌다(PaywallView 가 isPro 를 보고 dismiss 한다).
    ///   · `-JanjanShowPaywall` 로 뜨자마자 연다. 페이월은 잠긴 기능을 눌러야
    ///     열려서 걸어 들어갈 길이 마땅치 않다.
    ///
    /// 값·가격은 스킴에 붙인 로컬 StoreKit 설정에서 온다. 그것이 없으면
    /// "불러오는 중" 카드가 찍히므로, 상품 줄이 뜰 때까지 기다린 뒤에 찍는다.
    private func capturePaywall() {
        app.terminate()
        app.launchEnvironment["JANJAN_FORCE_PRO"] = "0"
        app.launchArguments = ["-JanjanSeedDemoData", "-JanjanShowPaywall"]
        app.launch()

        // 상품을 불러오는 데 시간이 걸린다. 가격이 붙은 줄이 나올 때까지 본다.
        let plans = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "연간")
        ).firstMatch
        _ = plans.waitForExistence(timeout: 30)
        settle()
        capture("26-구독")

        // 심사는 상품 이름·기간·가격과 자동 갱신 안내가 한 장에 보여야 한다.
        // 긴 화면이라 아래쪽을 따로 한 장 더 찍는다.
        scrollToBottom(limit: 4)
        capture("26b-구독-아래")
    }

    // MARK: - 조각

    /// 더 내려갈 데가 없을 때까지 내린다.
    ///
    /// 정해진 횟수만큼 쓸어 올리면 화면이 길어질 때 바닥에 못 닿는다.
    /// 화면이 더 안 바뀔 때까지 민다. 스크롤이 없는 화면에서는 한 번에 끝난다.
    private func scrollToBottom(limit: Int = 8) {
        var previous = app.windows.firstMatch.screenshot().pngRepresentation
        for _ in 0..<limit {
            app.swipeUp()
            settle()
            let current = app.windows.firstMatch.screenshot().pngRepresentation
            if current == previous { return }
            previous = current
        }
    }

    private func scrollToTop(limit: Int = 8) {
        for _ in 0..<limit { app.swipeDown() }
        settle()
    }

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

    /// 시트를 닫고, **정말 닫혔는지 확인한다.** 못 닫으면 실패로 끊는다 —
    /// 다음 캡처들이 시트 위에서 엉뚱한 사진을 남기는 것보다 낫다.
    private func dismissSheet(file: StaticString = #filePath, line: UInt = #line) {
        if !tryDismissSheet() {
            XCTFail("시트가 닫히지 않았습니다", file: file, line: line)
        }
    }

    /// "닫기" 는 시트 뿌리에만 있다. 시트 안에서 다음 화면으로 밀고 들어가 있으면
    /// (약 추가 -> 직접 입력) 닫기가 없어서, 예전에는 swipeDown 으로 떨어졌다.
    /// 그런데 폼 위에서의 swipeDown 은 시트를 닫는 대신 내용만 스크롤한다.
    /// 그래서 먼저 뿌리로 나온 다음 닫는다.
    private func tryDismissSheet(attempts: Int = 6) -> Bool {
        for _ in 0..<attempts {
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
            if isTabBarReachable { return true }
        }
        return isTabBarReachable
    }

    private var captured: Set<String> = []

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
        captured.insert(name)
    }

    /// 스토어에 꼭 필요한 화면. **없으면 테스트를 빨갛게 만든다.**
    ///
    /// 여태 한 장이 빠져도 초록으로 끝났다. 어느 화면이 안 찍혔는지는
    /// 사진 목록을 세어 보기 전에는 몰랐고, 두 세트를 그렇게 흘려보냈다.
    /// 화면을 못 찾으면 그 자리에서 알려 주어야 다음 런을 낭비하지 않는다.
    private static let required = [
        "01-오늘", "02-약", "03-약-상세", "04-기록",
        "08-처방-기록", "15-지나간-시간대", "20-용량변경-전후",
        "26-구독", "26b-구독-아래"
    ]

    private func assertRequiredCaptures() {
        let missing = Self.required.filter { !captured.contains($0) }
        XCTAssertTrue(
            missing.isEmpty,
            "스토어에 쓰는 화면을 못 찍었습니다: \(missing.joined(separator: ", "))"
        )
    }
}
