import Foundation

// data/*.json 을 그대로 읽는 Codable 구조체와 로더.
//
// 원본은 저장소 루트의 `data/` 이고, 여기 Resources/ 안의 파일은 그 사본이다.
// 지금은 손으로 맞춰 복사한다(data/README.md 참고).

// MARK: - 증상 카탈로그

public enum SymptomAuxField: String, Codable, Sendable, CaseIterable {
    /// 보조 입력 없음. 촉발 상황 태그는 공통 입력으로 따로 받는다.
    case none
    /// 수면 항목의 시간 입력.
    case time
    /// 관련 약 + 복용 후 경과 시간.
    case medication
}

public struct SymptomGroup: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let nameKo: String
    public let auxNote: String?
}

public struct SymptomItem: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let nameKo: String
    public let group: String
    public let auxField: SymptomAuxField
    /// 저장할 때 안전 카드를 띄우는 항목(자해·자살 생각).
    public let safety: Bool?

    /// nil 을 매번 풀어 쓰지 않도록.
    public var isSafetyItem: Bool { safety == true }
}

public struct SymptomCatalog: Codable, Hashable, Sendable {
    public let version: String
    public let updated: String
    public let note: String?
    public let groups: [SymptomGroup]
    public let symptoms: [SymptomItem]

    public static let empty = SymptomCatalog(
        version: "0", updated: "", note: nil, groups: [], symptoms: []
    )

    public func symptom(id: String) -> SymptomItem? {
        symptoms.first { $0.id == id }
    }

    public func symptoms(inGroup groupID: String) -> [SymptomItem] {
        symptoms.filter { $0.group == groupID }
    }

    /// 안전 카드를 띄워야 하는 항목들.
    public var safetyItems: [SymptomItem] {
        symptoms.filter(\.isSafetyItem)
    }
}

// MARK: - 감정 단어

public struct EmotionGroup: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let nameKo: String
}

public struct EmotionWord: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let nameKo: String
    public let group: String
}

public struct EmotionWordList: Codable, Hashable, Sendable {
    public let version: String
    public let updated: String
    public let note: String?
    public let groups: [EmotionGroup]
    public let words: [EmotionWord]

    public static let empty = EmotionWordList(
        version: "0", updated: "", note: nil, groups: [], words: []
    )

    public func word(id: String) -> EmotionWord? {
        words.first { $0.id == id }
    }

    public func words(inGroup groupID: String) -> [EmotionWord] {
        words.filter { $0.group == groupID }
    }
}

// MARK: - 질문 카드

public struct QuestionCard: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let textKo: String
}

public struct QuestionCardDeck: Codable, Hashable, Sendable {
    public let version: String
    public let updated: String
    public let note: String?
    public let cards: [QuestionCard]

    public static let empty = QuestionCardDeck(version: "0", updated: "", note: nil, cards: [])

    /// 하루 1장. 같은 날엔 항상 같은 카드가 나오고, 넘기면 다음 카드로 간다.
    public func card(for date: Date, offset: Int = 0, calendar: Calendar = .current) -> QuestionCard? {
        guard !cards.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let index = ((day + offset) % cards.count + cards.count) % cards.count
        return cards[index]
    }
}

// MARK: - 로더

public enum CatalogError: Error, CustomStringConvertible {
    case missingResource(String)
    case decodingFailed(String, underlying: Error)

    public var description: String {
        switch self {
        case .missingResource(let name):
            return "번들에서 \(name).json 을 찾지 못했습니다."
        case .decodingFailed(let name, let underlying):
            return "\(name).json 을 읽지 못했습니다: \(underlying)"
        }
    }
}

public enum CatalogLoader {

    /// 패키지 리소스 번들. SPM 이 만들어 주므로 강제 언래핑하지 않는다.
    public static var bundle: Bundle { Bundle.module }

    public static func decode<T: Decodable>(_ type: T.Type, resource: String) throws -> T {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            throw CatalogError.missingResource(resource)
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch let error as CatalogError {
            throw error
        } catch {
            throw CatalogError.decodingFailed(resource, underlying: error)
        }
    }

    public static func symptomCatalog() throws -> SymptomCatalog {
        try decode(SymptomCatalog.self, resource: "symptom_catalog")
    }

    public static func emotionWords() throws -> EmotionWordList {
        try decode(EmotionWordList.self, resource: "emotion_words")
    }

    public static func questionCards() throws -> QuestionCardDeck {
        try decode(QuestionCardDeck.self, resource: "question_cards")
    }
}

/// 앱 어디서나 쓰는 읽기 전용 카탈로그. 첫 접근에 한 번만 읽고 캐시한다.
///
/// 로딩이 실패해도 앱은 계속 떠야 하므로 빈 카탈로그로 떨어진다.
/// 빈 카탈로그로 떨어졌는지는 `isHealthy` 로 확인할 수 있고, 테스트가 이를 감시한다.
public enum Catalogs {
    public static let symptoms: SymptomCatalog = (try? CatalogLoader.symptomCatalog()) ?? .empty
    public static let emotions: EmotionWordList = (try? CatalogLoader.emotionWords()) ?? .empty
    public static let questions: QuestionCardDeck = (try? CatalogLoader.questionCards()) ?? .empty

    public static var isHealthy: Bool {
        !symptoms.symptoms.isEmpty && !emotions.words.isEmpty && !questions.cards.isEmpty
    }

    /// 워치 빠른 기록에 먼저 보여 줄 증상 6개. v1 은 고정 목록이고,
    /// v2 에서 "자주 쓰는 순" 으로 바꾼다.
    public static let watchQuickSymptomIDs: [String] = [
        "anxiety_restless",
        "low_mood",
        "trouble_falling_asleep",
        "no_energy",
        "drowsiness",
        "headache"
    ]

    public static var watchQuickSymptoms: [SymptomItem] {
        watchQuickSymptomIDs.compactMap { symptoms.symptom(id: $0) }
    }
}
