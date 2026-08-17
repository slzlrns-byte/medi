import XCTest
@testable import JanjanCore

/// 번들 JSON 이 실제로 읽히는지. 리소스 경로가 어긋나면 앱은 조용히 빈 목록을 보여 주기 때문에
/// 사람이 알아채기 전에 여기서 잡아야 한다.
final class CatalogTests: XCTestCase {

    func testSymptomCatalogLoads() throws {
        let catalog = try CatalogLoader.symptomCatalog()
        XCTAssertFalse(catalog.symptoms.isEmpty)
        XCTAssertEqual(catalog.groups.count, 3)
        XCTAssertGreaterThan(catalog.symptoms.count, 40)

        // 모든 증상은 실제로 존재하는 묶음에 속해야 한다.
        let groupIDs = Set(catalog.groups.map(\.id))
        for symptom in catalog.symptoms {
            XCTAssertTrue(groupIDs.contains(symptom.group), "고아 증상: \(symptom.id)")
        }
    }

    func testSelfHarmItemCarriesSafetyFlag() throws {
        let catalog = try CatalogLoader.symptomCatalog()
        let item = try XCTUnwrap(catalog.symptom(id: "self_harm_thoughts"))
        XCTAssertEqual(item.nameKo, "자해·자살 생각")
        XCTAssertTrue(item.isSafetyItem, "이 항목을 저장할 때는 안전 카드가 떠야 한다")
        XCTAssertEqual(catalog.safetyItems.count, 1)

        let entry = SymptomEntry(symptomID: "self_harm_thoughts", severity: 7, startedAt: Date())
        XCTAssertTrue(entry.needsSafetyCard(catalog: catalog))

        let benign = SymptomEntry(symptomID: "headache", severity: 3, startedAt: Date())
        XCTAssertFalse(benign.needsSafetyCard(catalog: catalog))
    }

    func testSymptomAuxFieldsDecode() throws {
        let catalog = try CatalogLoader.symptomCatalog()
        let plain = try XCTUnwrap(catalog.symptom(id: "anxiety_restless"))
        let sleep = try XCTUnwrap(catalog.symptom(id: "trouble_falling_asleep"))
        let sideEffect = try XCTUnwrap(catalog.symptom(id: "drowsiness"))

        XCTAssertEqual(plain.auxField, SymptomAuxField.none)
        XCTAssertEqual(sleep.auxField, SymptomAuxField.time)
        XCTAssertEqual(sideEffect.auxField, SymptomAuxField.medication)
    }

    func testEmotionWordsLoad() throws {
        let list = try CatalogLoader.emotionWords()
        XCTAssertEqual(list.words.count, 36)
        XCTAssertEqual(list.groups.count, 3)
        XCTAssertEqual(list.word(id: "calm")?.nameKo, "평온")
        XCTAssertEqual(list.words(inGroup: "good").count, 10)
    }

    func testQuestionCardsLoad() throws {
        let deck = try CatalogLoader.questionCards()
        XCTAssertEqual(deck.cards.count, 30)
        XCTAssertFalse(deck.cards.contains { $0.textKo.isEmpty })
    }

    func testQuestionCardIsStableWithinADayAndAdvancesWithOffset() throws {
        let deck = try CatalogLoader.questionCards()
        let morning = Fixed.date(2026, 8, 17, 9, 0)
        let evening = Fixed.date(2026, 8, 17, 23, 0)

        let a = try XCTUnwrap(deck.card(for: morning, calendar: Fixed.calendar))
        let b = try XCTUnwrap(deck.card(for: evening, calendar: Fixed.calendar))
        XCTAssertEqual(a.id, b.id, "같은 날엔 같은 카드")

        let next = try XCTUnwrap(deck.card(for: morning, offset: 1, calendar: Fixed.calendar))
        XCTAssertNotEqual(a.id, next.id, "넘기면 다음 카드")

        let tomorrow = try XCTUnwrap(
            deck.card(for: Fixed.date(2026, 8, 18, 9, 0), calendar: Fixed.calendar)
        )
        XCTAssertEqual(next.id, tomorrow.id)
    }

    func testWatchQuickSymptomsAllResolve() {
        let items = Catalogs.watchQuickSymptoms
        XCTAssertEqual(items.count, Catalogs.watchQuickSymptomIDs.count)
        XCTAssertEqual(items.count, 6)
    }

    func testCatalogsCacheIsHealthy() {
        XCTAssertTrue(Catalogs.isHealthy, "세 카탈로그 중 하나라도 빈 목록으로 떨어지면 실패")
    }
}
