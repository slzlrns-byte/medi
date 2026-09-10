import XCTest
@testable import JanjanCore

/// design/tokens.json 과 Tokens.swift 가 어긋나지 않도록 지키는 최소한의 그물.
final class TokensTests: XCTestCase {

    func testEveryColorHasParsableLightAndDarkHexInEveryTheme() {
        for theme in JanjanTheme.allCases {
            for token in JanjanColor.allCases {
                XCTAssertNotNil(
                    JanjanRGB(hex: token.lightHex(theme)),
                    "라이트 값 파싱 실패: \(theme) \(token)"
                )
                XCTAssertNotNil(
                    JanjanRGB(hex: token.darkHex(theme)),
                    "다크 값 파싱 실패: \(theme) \(token)"
                )
                XCTAssertNotEqual(
                    token.lightHex(theme), token.darkHex(theme),
                    "\(theme) \(token) 은 라이트/다크가 같으면 안 된다"
                )
            }
        }
        XCTAssertEqual(JanjanColor.allCases.count, 23)
        XCTAssertEqual(JanjanTheme.allCases.count, 3)
    }

    func testCoreBrandColorsMatchTheDesignDocument() {
        // 바탕·글자·선은 모노톤이라 테마와 무관하다 (2026-09-10 결정).
        for theme in JanjanTheme.allCases {
            XCTAssertEqual(JanjanColor.fog.lightHex(theme), "#F7F7F6")
            XCTAssertEqual(JanjanColor.ink.lightHex(theme), "#1A1A19")
            XCTAssertEqual(JanjanColor.fog.darkHex(theme), "#161716")
            XCTAssertEqual(JanjanColor.surface.darkHex(theme), "#1F201E")
        }

        // 테마 색 표본 하나씩 — 표 전체를 다시 적지 않고 어긋남만 잡는다.
        XCTAssertEqual(JanjanColor.sage.lightHex(.sprout), "#D5E4C9")
        XCTAssertEqual(JanjanColor.butter.lightHex(.sunset), "#FFE8CD")
        XCTAssertEqual(JanjanColor.mood7.lightHex(.sky), "#4E97D1")
        XCTAssertEqual(JanjanColor.mood1.lightHex(.sky), "#A183C2")

        // 테마를 모르는 곳의 기본은 풋사과 크림이고, 기본 인자가 그 값을 쓴다.
        XCTAssertEqual(JanjanTheme.standard, .sprout)
        XCTAssertEqual(JanjanColor.mood7.lightHex(), JanjanColor.mood7.lightHex(.sprout))

        // tokens.json 은 바탕을 `paper` 라고 부른다.
        XCTAssertEqual(JanjanColor.fog.tokenKey, "paper")
        XCTAssertEqual(JanjanColor.sageInk.tokenKey, "sage-ink")
    }

    func testThemeLabelsAndStorageRoundTrip() {
        for theme in JanjanTheme.allCases {
            XCTAssertEqual(JanjanTheme(rawValue: theme.rawValue), theme)
            XCTAssertFalse(theme.labelKo.isEmpty)
            XCTAssertFalse(theme.detailKo.isEmpty)
        }
        // 저장된 값이 이상해도 조용히 기본으로 돌아간다.
        XCTAssertNil(JanjanTheme(rawValue: "없는테마"))
    }

    func testWatchSnapshotCarriesTheTheme() throws {
        let snapshot = WatchSnapshot(
            dateText: "9/10",
            slots: [],
            remainingCountToday: 0,
            themeRaw: JanjanTheme.sky.rawValue
        )
        XCTAssertEqual(snapshot.theme, .sky)

        // 테마 키가 없던 옛 스냅샷도 기본 테마로 되살아난다.
        // 워치에 마지막으로 건너간 그림은 앱을 지우기 전까지 남아 있기 때문이다.
        let legacy = Data("""
        {"generatedAt":0,"dateText":"9/10","slots":[],"remainingCountToday":0}
        """.utf8)
        let restored = try JSONDecoder().decode(WatchSnapshot.self, from: legacy)
        XCTAssertEqual(restored.theme, .standard)
        XCTAssertTrue(restored.isPro)
    }

    func testSlotLineWithoutIDsStillDecodes() throws {
        // 약 ID 키가 없던 시절의 줄. 화면은 그려지고, 기록만 못 보낸다.
        let legacy = Data("""
        {"slotKey":"morning","labelKo":"아침","timeText":"08:00",\
        "medicationNames":["에스시탈로프람"],"isCompleted":false}
        """.utf8)
        let line = try JSONDecoder().decode(WatchSnapshot.SlotLine.self, from: legacy)
        XCTAssertEqual(line.medicationIDs, [])
        XCTAssertEqual(line.medicationNames, ["에스시탈로프람"])
    }

    func testHexParsing() {
        let ink = JanjanRGB(hex: "#1C1C1B")
        XCTAssertNotNil(ink)
        XCTAssertEqual(ink?.red ?? -1, 28.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(ink?.green ?? -1, 28.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(ink?.blue ?? -1, 27.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(ink?.alpha ?? -1, 1.0, accuracy: 0.0001)

        XCTAssertNotNil(JanjanRGB(hex: "F2F2F0"), "# 없이도 읽는다")
        XCTAssertNotNil(JanjanRGB(hex: "#1C1C1B80"), "알파 8자리도 읽는다")
        XCTAssertNil(JanjanRGB(hex: "#GGGGGG"))
        XCTAssertNil(JanjanRGB(hex: "#FFF"))
        XCTAssertNil(JanjanRGB(hex: ""))
    }

    func testMoodScaleHasSevenStepsWithLabels() {
        XCTAssertEqual(JanjanMood.scores, [-3, -2, -1, 0, 1, 2, 3])
        XCTAssertEqual(JanjanMood.colors.count, 7)
        XCTAssertEqual(JanjanMood.labelsKo.count, 7)

        XCTAssertEqual(JanjanMood.color(forScore: -3), .mood1)
        XCTAssertEqual(JanjanMood.color(forScore: 0), .mood4)
        XCTAssertEqual(JanjanMood.color(forScore: 3), .mood7)
        XCTAssertEqual(JanjanMood.label(forScore: -3), "매우 힘듦")
        XCTAssertEqual(JanjanMood.label(forScore: 3), "좋음")

        // 범위 밖 값이 들어와도 크래시하지 않는다.
        XCTAssertEqual(JanjanMood.color(forScore: -99), .mood1)
        XCTAssertEqual(JanjanMood.color(forScore: 99), .mood7)
    }

    func testMoodModelClampsAndLabels() {
        XCTAssertEqual(CheckIn.Mood(5).score, 3)
        XCTAssertEqual(CheckIn.Mood(-9).score, -3)
        XCTAssertEqual(CheckIn.Mood(0).labelKo, "그저 그럼")
        XCTAssertEqual(CheckIn.Mood(-3).index, 0)
        XCTAssertEqual(CheckIn.Mood(3).index, 6)
    }

    func testRadiiAndSpacingMatchTheDesignDocument() {
        XCTAssertEqual(JanjanRadius.card, 24)
        XCTAssertEqual(JanjanRadius.tile, 28)
        XCTAssertEqual(JanjanRadius.row, 18)
        XCTAssertEqual(JanjanSpacing.all, [4, 8, 12, 16, 20, 24, 32])
    }

    func testBundledFontFileNamesMatchPostScriptNames() {
        // UIAppFonts(project.yml)에 적은 파일명과 코드가 부르는 이름이 짝을 이뤄야 한다.
        XCTAssertEqual(JanjanFontName.bundledFiles.count, 11)
        XCTAssertTrue(JanjanFontName.bundledFiles.contains("\(JanjanFontName.displayLight).otf"))
        XCTAssertTrue(JanjanFontName.bundledFiles.contains("\(JanjanFontName.bodyRegular).otf"))
        XCTAssertTrue(JanjanFontName.bundledFiles.contains("\(JanjanFontName.plexRegular).ttf"))
        XCTAssertTrue(JanjanFontName.bundledFiles.contains("\(JanjanFontName.gowunRegular).ttf"))
        XCTAssertTrue(JanjanFontName.bundledFiles.allSatisfy { $0.hasSuffix(".otf") || $0.hasSuffix(".ttf") })
    }

    func testSlotStorageKeysRoundTrip() {
        for slot in DoseSlot.presets {
            XCTAssertEqual(DoseSlot(storageKey: slot.storageKey), slot)
        }
        let custom = DoseSlot.custom(TimeOfDay(hour: 6, minute: 45))
        XCTAssertEqual(custom.storageKey, "custom-06:45")
        XCTAssertEqual(DoseSlot(storageKey: "custom-06:45"), custom)
        XCTAssertNil(DoseSlot(storageKey: "custom-99:99"))
        XCTAssertNil(DoseSlot(storageKey: "저녁"))
    }

    func testWatchMessageRoundTripsThroughDictionary() {
        let original = WatchMessage.doseAction(
            medicationIDs: [Fixed.medA, Fixed.medB],
            slotKey: DoseSlot.bedtime.storageKey,
            action: .taken
        )
        let restored = WatchMessage(payload: original.payload)
        XCTAssertEqual(restored, original)

        let mood = WatchMessage.mood(score: -2, at: Fixed.date(2026, 8, 17, 21))
        XCTAssertEqual(WatchMessage(payload: mood.payload), mood)

        XCTAssertNil(WatchMessage(payload: ["type": "무엇"]))
    }

    func testCrisisContactsAreDialable() {
        XCTAssertEqual(Janjan.crisisContactsKR.count, 2)
        XCTAssertEqual(Janjan.crisisContactsKR[0].number, "109")
        XCTAssertEqual(Janjan.crisisContactsKR[1].dialDigits, "15770199")
        XCTAssertEqual(Janjan.cloudKitContainerID, "iCloud.com.thejanjan.app")
    }
}
