import Foundation

/// 약 모양으로 찾기(낱알식별)의 순수 로직.
///
/// 데이터는 앱이 번들 JSON 으로 들고 오고, 여기는 거르고 순위 매기는 일만 한다.
/// **단정하지 않는다** - 결과는 언제나 "추측되는 후보" 이고, 화면은 반드시
/// "정확한 것은 의사나 약사에게 확인해 주세요" 를 함께 보인다(설계 원칙 D12).
public enum PillFinder {

    /// 알약 하나의 겉모습. 한국 식약처 낱알식별 항목과 미국 SPL 물리 특성의
    /// 공통 분모로 추렸다 - 어느 쪽 데이터든 이 모양으로 맞춰 넣는다.
    public struct Pill: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        /// 제품명. 데이터가 온 나라의 말 그대로 둔다(사용자의 약봉투에 적힌 이름과 같아야 알아본다).
        public var name: String
        /// "10mg" 처럼 화면에 붙는 용량 문자열. 모르면 빈 문자열.
        public var strengthText: String
        public var shape: Shape
        /// 앞면 색. 양면 색이 다르면 back 에 따로 담는다.
        public var colorFront: PillColor
        public var colorBack: PillColor?
        /// 각인. 없으면 빈 문자열. 분리선 문자(|, -)는 데이터 그대로 둔다.
        public var imprintFront: String
        public var imprintBack: String
        /// 낱알 사진 URL. 없으면 nil - 화면은 사진 없이도 성립해야 한다.
        public var imageURLString: String?

        public init(
            id: String,
            name: String,
            strengthText: String = "",
            shape: Shape,
            colorFront: PillColor,
            colorBack: PillColor? = nil,
            imprintFront: String = "",
            imprintBack: String = "",
            imageURLString: String? = nil
        ) {
            self.id = id
            self.name = name
            self.strengthText = strengthText
            self.shape = shape
            self.colorFront = colorFront
            self.colorBack = colorBack
            self.imprintFront = imprintFront
            self.imprintBack = imprintBack
            self.imageURLString = imageURLString
        }
    }

    /// 제형 겉모양. 식약처 표준 어휘를 기준으로 하고, 미국 SPL 모양 코드도 여기에 맞춘다.
    public enum Shape: String, Codable, Sendable, CaseIterable {
        case round        // 원형
        case oval         // 타원형
        case oblong       // 장방형(캡슐형 정제 포함)
        case capsule      // 경질캡슐
        case triangle     // 삼각형
        case square       // 사각형
        case diamond      // 마름모형
        case pentagon     // 오각형
        case hexagon      // 육각형
        case octagon      // 팔각형
        case other        // 기타

        public var labelKo: String {
            switch self {
            case .round: return "원형"
            case .oval: return "타원형"
            case .oblong: return "장방형"
            case .capsule: return "캡슐"
            case .triangle: return "삼각형"
            case .square: return "사각형"
            case .diamond: return "마름모"
            case .pentagon: return "오각형"
            case .hexagon: return "육각형"
            case .octagon: return "팔각형"
            case .other: return "기타"
            }
        }

        public var labelEn: String {
            switch self {
            case .round: return "Round"
            case .oval: return "Oval"
            case .oblong: return "Oblong"
            case .capsule: return "Capsule"
            case .triangle: return "Triangle"
            case .square: return "Square"
            case .diamond: return "Diamond"
            case .pentagon: return "Pentagon"
            case .hexagon: return "Hexagon"
            case .octagon: return "Octagon"
            case .other: return "Other"
            }
        }

        public func label(_ language: JanjanLanguage) -> String {
            language == .english ? labelEn : labelKo
        }
    }

    /// 알약 색. 식약처 표준 색 이름과 미국 SPL 색 코드의 합집합.
    public enum PillColor: String, Codable, Sendable, CaseIterable {
        case white
        case yellow
        case orange
        case pink
        case red
        case brown
        case lightGreen   // 연두
        case green
        case teal         // 청록
        case blue
        case navy         // 남색
        case wine         // 자주
        case purple
        case gray
        case black
        case clear        // 투명

        public var labelKo: String {
            switch self {
            case .white: return "하양"
            case .yellow: return "노랑"
            case .orange: return "주황"
            case .pink: return "분홍"
            case .red: return "빨강"
            case .brown: return "갈색"
            case .lightGreen: return "연두"
            case .green: return "초록"
            case .teal: return "청록"
            case .blue: return "파랑"
            case .navy: return "남색"
            case .wine: return "자주"
            case .purple: return "보라"
            case .gray: return "회색"
            case .black: return "검정"
            case .clear: return "투명"
            }
        }

        public var labelEn: String {
            switch self {
            case .white: return "White"
            case .yellow: return "Yellow"
            case .orange: return "Orange"
            case .pink: return "Pink"
            case .red: return "Red"
            case .brown: return "Brown"
            case .lightGreen: return "Light green"
            case .green: return "Green"
            case .teal: return "Teal"
            case .blue: return "Blue"
            case .navy: return "Navy"
            case .wine: return "Wine"
            case .purple: return "Purple"
            case .gray: return "Gray"
            case .black: return "Black"
            case .clear: return "Clear"
            }
        }

        public func label(_ language: JanjanLanguage) -> String {
            language == .english ? labelEn : labelKo
        }
    }

    /// 사용자가 고른 조건. 전부 선택 사항 - 아무것도 안 고르면 결과도 없다
    /// (2만 개를 다 들어 보이는 것은 찾기가 아니다).
    public struct Query: Sendable, Equatable {
        public var shape: Shape?
        public var color: PillColor?
        public var imprint: String

        public init(shape: Shape? = nil, color: PillColor? = nil, imprint: String = "") {
            self.shape = shape
            self.color = color
            self.imprint = imprint
        }

        public var isEmpty: Bool {
            shape == nil && color == nil
                && imprint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// 결과 상한. 후보가 이보다 많으면 조건을 더 좁히라는 뜻이지,
    /// 스크롤로 다 보라는 뜻이 아니다.
    public static let maxResults = 30

    /// 조건에 맞는 후보를 각인 일치가 강한 순서로 돌려준다.
    ///
    /// - 각인은 대소문자·공백·구분 기호를 지우고 비교한다 ("A 10" 과 "A10" 은 같은 각인이다).
    /// - 색은 앞면이든 뒷면이든 한 면만 맞아도 통과 - 사용자는 어느 쪽이 앞인지 모른다.
    /// - 순위: 각인 정확 일치 > 각인 시작 일치 > 각인 포함 > 나머지. 같은 급에서는 이름순.
    public static func search(_ query: Query, in pills: [Pill]) -> [Pill] {
        guard !query.isEmpty else { return [] }
        let needle = normalizeImprint(query.imprint)

        struct Ranked {
            let pill: Pill
            let rank: Int
        }

        let ranked: [Ranked] = pills.compactMap { pill in
            if let shape = query.shape, pill.shape != shape { return nil }
            if let color = query.color {
                let matchesFront = pill.colorFront == color
                let matchesBack = pill.colorBack == color
                guard matchesFront || matchesBack else { return nil }
            }

            guard !needle.isEmpty else { return Ranked(pill: pill, rank: 3) }
            let front = normalizeImprint(pill.imprintFront)
            let back = normalizeImprint(pill.imprintBack)
            if front == needle || back == needle { return Ranked(pill: pill, rank: 0) }
            if front.hasPrefix(needle) || back.hasPrefix(needle) { return Ranked(pill: pill, rank: 1) }
            if front.contains(needle) || back.contains(needle) { return Ranked(pill: pill, rank: 2) }
            return nil
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.pill.name < rhs.pill.name
            }
            .prefix(maxResults)
            .map(\.pill)
    }

    /// 각인 비교용 정규화: 대문자로 통일하고 글자·숫자만 남긴다.
    /// "GD-10", "gd 10", "GD10" 이 전부 같은 각인으로 읽힌다.
    static func normalizeImprint(_ text: String) -> String {
        text.uppercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}

/// 번들에 실린 낱알 데이터. 첫 접근에 한 번만 읽고 캐시한다(Catalogs 와 같은 규칙).
///
/// 파일이 없으면 빈 목록이다 - **지어낸 약 데이터를 넣는 것은 금지**라서,
/// 실데이터 파이프라인(식약처 공공데이터)이 `pill_catalog.json` 을 만들어
/// 넣기 전까지는 화면이 "아직 실려 있지 않아요" 로 안내한다.
public enum PillCatalog {
    public static let pills: [PillFinder.Pill] =
        (try? CatalogLoader.decode([PillFinder.Pill].self, resource: "pill_catalog")) ?? []
}
