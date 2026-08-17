import XCTest
@testable import JanjanCore

/// design/tokens.json 과 Tokens.swift 가 어긋나지 않도록 지키는 최소한의 그물.
final class TokensTests: XCTestCase {

    func testEveryColorHasParsableLightAndDarkHex() {
        for token in JanjanColor.allCases {
            XCTAssertNotNil(JanjanRGB(hex: token.lightHex), "라이트 값 파싱 실패: \(token)")
            XCTAssertNotNil(JanjanRGB(hex: token.darkHex), "다크 값 파싱 실패: \(token)")
            XCTAssertNotEqual(token.lightHex, token.darkHex, "\(token) 은 라이트/다크가 같으면 안 된다")
        }
        XCTAssertEqual(JanjanColor.allCases.count, 23)
    }

    func testCoreBrandColorsMatchTheDesignDocument() {
        XCTAssertEqual(JanjanColor.fog.lightHex, "#F2F2F0")
        XCTAssertEqual(JanjanColor.sage.lightHex, "#CBDAD5")
        XCTAssertEqual(JanjanColor.lav.lightHex, "#DDD9F2")
        XCTAssertEqual(JanjanColor.butter.lightHex, "#F1EEA9")
        XCTAssertEqual(JanjanColor.peach.lightHex, "#F4E1D6")
        XCTAssertEqual(JanjanColor.ink.lightHex, "#1C1C1B")

        XCTAssertEqual(JanjanColor.fog.darkHex, "#161716")
        XCTAssertEqual(JanjanColor.surface.darkHex, "#1F201E")

        // tokens.json 은 바탕을 `paper` 라고 부른다.
        XCTAssertEqual(JanjanColor.fog.tokenKey, "paper")
        XCTAssertEqual(JanjanColor.sageInk.tokenKey, "sage-ink")
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
        XCTAssertEqual(JanjanFontName.bundledFiles.count, 6)
        XCTAssertTrue(JanjanFontName.bundledFiles.contains("\(JanjanFontName.displayLight).otf"))
        XCTAssertTrue(JanjanFontName.bundledFiles.contains("\(JanjanFontName.bodyRegular).otf"))
        XCTAssertTrue(JanjanFontName.bundledFiles.allSatisfy { $0.hasSuffix(".otf") })
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
