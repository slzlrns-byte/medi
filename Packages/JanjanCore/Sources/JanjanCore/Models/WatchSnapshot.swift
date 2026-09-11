import Foundation

/// 아이폰이 워치로 보내는 가벼운 오늘 요약.
///
/// 워치는 재고를 계산하지 않고 SwiftData 도 쓰지 않는다(설계 10절).
/// 데이터의 주인은 폰이고, 워치는 이 스냅샷을 그대로 그린다.
public struct WatchSnapshot: Codable, Hashable, Sendable {

    public struct SlotLine: Codable, Hashable, Sendable, Identifiable {
        public var id: String { slotKey }
        /// `DoseSlot.storageKey`
        public let slotKey: String
        public let labelKo: String
        /// "22:30"
        public let timeText: String
        /// 그 시간대에 예정된 약 이름들.
        public let medicationNames: [String]
        /// 같은 순서의 약 ID. 워치가 "먹었어요" 를 보낼 때 이 ID 로 말한다 —
        /// 폰의 저장 규칙(DoseRecorder)이 ID 단위라, 이름만으로는 기록할 수 없다.
        public let medicationIDs: [UUID]
        /// 이미 기록이 끝났는지.
        public let isCompleted: Bool

        public init(
            slotKey: String,
            labelKo: String,
            timeText: String,
            medicationNames: [String],
            medicationIDs: [UUID] = [],
            isCompleted: Bool
        ) {
            self.slotKey = slotKey
            self.labelKo = labelKo
            self.timeText = timeText
            self.medicationNames = medicationNames
            self.medicationIDs = medicationIDs
            self.isCompleted = isCompleted
        }

        private enum CodingKeys: String, CodingKey {
            case slotKey, labelKo, timeText, medicationNames, medicationIDs, isCompleted
        }

        /// ID 키가 없던 시절의 스냅샷도 되살아난다. 그 줄로는 기록을 못 보내지만
        /// 화면은 그대로 그려진다 — 다음 스냅샷이 오면 ID 가 채워진다.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            slotKey = try container.decode(String.self, forKey: .slotKey)
            labelKo = try container.decode(String.self, forKey: .labelKo)
            timeText = try container.decode(String.self, forKey: .timeText)
            medicationNames = try container.decode([String].self, forKey: .medicationNames)
            medicationIDs = try container.decodeIfPresent([UUID].self, forKey: .medicationIDs) ?? []
            isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        }

        /// 이름이 비어 있어도 ID 가 있으면 약은 있는 것이다 - 이름 가리기가 이름만
        /// 비워 보내므로, 개수까지 "없음" 으로 말하면 가림이 거짓말이 된다.
        private var medicationCount: Int {
            medicationNames.isEmpty ? medicationIDs.count : medicationNames.count
        }

        public var summaryKo: String {
            guard medicationCount > 0 else { return "예정된 약 없음" }
            return "\(medicationCount)종"
        }

        public func summary(_ language: JanjanLanguage) -> String {
            guard language == .english else { return summaryKo }
            guard medicationCount > 0 else { return "Nothing scheduled" }
            return medicationCount == 1 ? "1 med" : "\(medicationCount) meds"
        }
    }

    /// 필요할 때 먹는 약 한 줄. 워치는 이걸 눌러 그 순간의 복용을 폰으로 보낸다.
    public struct AsNeededLine: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID { medicationID }
        public let medicationID: UUID
        /// "로라제팜 0.5mg" - 폰이 구워 보낸 표시용 이름.
        public let title: String
        /// 누르면 기록될 개수. 폰에서 지난번에 먹은 개수를 따른다(없으면 1).
        public let quantity: Decimal
        /// 오늘 이미 기록된 시각들("14:19"). 사실만 보여 주고 세지 않는다.
        public let takenTodayTexts: [String]

        public init(medicationID: UUID, title: String, quantity: Decimal, takenTodayTexts: [String] = []) {
            self.medicationID = medicationID
            self.title = title
            self.quantity = quantity
            self.takenTodayTexts = takenTodayTexts
        }
    }

    public let generatedAt: Date
    /// "8/17"
    public let dateText: String
    public let slots: [SlotLine]
    /// 필요시(응급) 약들. 이 키가 없던 시절의 스냅샷은 빈 목록으로 되살아난다.
    public let asNeeded: [AsNeededLine]
    /// 오늘 아직 기록하지 않은 약 개수. 컴플리케이션에 그대로 쓴다.
    public let remainingCountToday: Int
    /// 워치 앱은 Pro 기능이다(무료/Pro 경계 결정). **판단은 폰이 한다.**
    /// 워치에 StoreKit 을 올리지 않는 이유는 이 앱의 원칙 그대로다 —
    /// 워치는 아무것도 계산하지 않고 받은 그림만 그린다.
    public let isPro: Bool
    /// 폰에서 고른 테마. 워치의 기분 원이 폰과 같은 색을 쓰기 위한 값이다.
    public let themeRaw: String
    /// 폰에서 고른 언어. 워치 화면 전체가 이것을 따른다 - 워치에는 설정이 없다.
    public let languageRaw: String

    public var theme: JanjanTheme {
        JanjanTheme(rawValue: themeRaw) ?? .standard
    }

    public var language: JanjanLanguage {
        JanjanLanguage(rawValue: languageRaw) ?? .standard
    }

    public init(
        generatedAt: Date = Date(),
        dateText: String,
        slots: [SlotLine],
        asNeeded: [AsNeededLine] = [],
        remainingCountToday: Int,
        isPro: Bool = true,
        themeRaw: String = JanjanTheme.standard.rawValue,
        languageRaw: String = JanjanLanguage.standard.rawValue
    ) {
        self.generatedAt = generatedAt
        self.dateText = dateText
        self.slots = slots
        self.asNeeded = asNeeded
        self.remainingCountToday = remainingCountToday
        self.isPro = isPro
        self.themeRaw = themeRaw
        self.languageRaw = languageRaw
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAt, dateText, slots, asNeeded, remainingCountToday, isPro, themeRaw, languageRaw
    }

    /// 키가 없던 시절의 스냅샷이 남아 있어도 되살아나게 한다.
    /// 워치에 마지막으로 건너간 그림은 앱을 지우기 전까지 그대로 남아 있다.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        dateText = try container.decode(String.self, forKey: .dateText)
        slots = try container.decode([SlotLine].self, forKey: .slots)
        asNeeded = try container.decodeIfPresent([AsNeededLine].self, forKey: .asNeeded) ?? []
        remainingCountToday = try container.decode(Int.self, forKey: .remainingCountToday)
        isPro = try container.decodeIfPresent(Bool.self, forKey: .isPro) ?? true
        themeRaw = try container.decodeIfPresent(String.self, forKey: .themeRaw)
            ?? JanjanTheme.standard.rawValue
        languageRaw = try container.decodeIfPresent(String.self, forKey: .languageRaw)
            ?? JanjanLanguage.standard.rawValue
    }

    /// 폰이 아직 아무것도 보내 주지 않았을 때. **잠긴 상태로 시작한다** —
    /// 기본을 열림으로 두면 첫 실행·미페어링에서 무료 사용자에게도 Pro 화면이
    /// 보이고, 거기서 보낸 기록은 폰이 조용히 버린다(QA 2026-09-10).
    public static let placeholder = WatchSnapshot(
        dateText: "—",
        slots: [],
        remainingCountToday: 0,
        isPro: false
    )

    /// 구독하지 않은 사용자의 워치에 보내는 그림. 오늘 일정은 담기지 않는다.
    public static func locked(
        dateText: String,
        generatedAt: Date = Date(),
        themeRaw: String = JanjanTheme.standard.rawValue,
        languageRaw: String = JanjanLanguage.standard.rawValue
    ) -> WatchSnapshot {
        WatchSnapshot(
            generatedAt: generatedAt,
            dateText: dateText,
            slots: [],
            remainingCountToday: 0,
            isPro: false,
            themeRaw: themeRaw,
            languageRaw: languageRaw
        )
    }
}

/// 워치 → 아이폰으로 흘려보내는 메시지.
///
/// WatchConnectivity 는 `[String: Any]` 만 받으므로 딕셔너리로 굽고 되살리는 코드를
/// 여기 한 곳에 모아 둔다. 양쪽 앱이 같은 타입을 쓰니 키가 어긋날 수 없다.
public enum WatchMessage: Hashable, Sendable {

    case doseAction(medicationIDs: [UUID], slotKey: String, action: DoseAction)
    /// 필요시(응급) 복용 한 번. 시간대가 없으므로 슬롯 없이 약과 시각만 말한다.
    case asNeededTaken(medicationID: UUID, quantity: Decimal, at: Date)
    case symptom(symptomID: String, severity: Int, at: Date)
    case mood(score: Int, at: Date)
    case requestSnapshot

    public enum DoseAction: String, Sendable, CaseIterable {
        case taken
        case skipped
        case snooze
    }

    // MARK: 키

    public enum Key {
        public static let type = "type"
        public static let medicationIDs = "medicationIDs"
        public static let slotKey = "slotKey"
        public static let action = "action"
        public static let medicationID = "medicationID"
        public static let quantity = "quantity"
        public static let symptomID = "symptomID"
        public static let severity = "severity"
        public static let score = "score"
        public static let timestamp = "timestamp"
        public static let snapshot = "snapshot"
    }

    private enum Kind: String {
        case doseAction
        case asNeededTaken
        case symptom
        case mood
        case requestSnapshot
    }

    // MARK: 굽기 / 되살리기

    public var payload: [String: Any] {
        switch self {
        case .doseAction(let medicationIDs, let slotKey, let action):
            return [
                Key.type: Kind.doseAction.rawValue,
                Key.medicationIDs: medicationIDs.map(\.uuidString),
                Key.slotKey: slotKey,
                Key.action: action.rawValue,
                Key.timestamp: Date().timeIntervalSince1970
            ]
        case .asNeededTaken(let medicationID, let quantity, let date):
            return [
                Key.type: Kind.asNeededTaken.rawValue,
                Key.medicationID: medicationID.uuidString,
                // Decimal 은 문자열로 굽는다 - Double 을 거치면 0.1 같은 값이 흔들린다.
                Key.quantity: NSDecimalNumber(decimal: quantity).stringValue,
                Key.timestamp: date.timeIntervalSince1970
            ]
        case .symptom(let symptomID, let severity, let date):
            return [
                Key.type: Kind.symptom.rawValue,
                Key.symptomID: symptomID,
                Key.severity: severity,
                Key.timestamp: date.timeIntervalSince1970
            ]
        case .mood(let score, let date):
            return [
                Key.type: Kind.mood.rawValue,
                Key.score: score,
                Key.timestamp: date.timeIntervalSince1970
            ]
        case .requestSnapshot:
            return [Key.type: Kind.requestSnapshot.rawValue]
        }
    }

    public init?(payload: [String: Any]) {
        guard let rawType = payload[Key.type] as? String,
              let kind = Kind(rawValue: rawType)
        else { return nil }

        let date: Date = {
            if let seconds = payload[Key.timestamp] as? Double {
                return Date(timeIntervalSince1970: seconds)
            }
            return Date()
        }()

        switch kind {
        case .doseAction:
            guard let rawIDs = payload[Key.medicationIDs] as? [String],
                  let slotKey = payload[Key.slotKey] as? String,
                  let rawAction = payload[Key.action] as? String,
                  let action = DoseAction(rawValue: rawAction)
            else { return nil }
            self = .doseAction(
                medicationIDs: rawIDs.compactMap(UUID.init(uuidString:)),
                slotKey: slotKey,
                action: action
            )
        case .asNeededTaken:
            guard let rawID = payload[Key.medicationID] as? String,
                  let medicationID = UUID(uuidString: rawID),
                  let rawQuantity = payload[Key.quantity] as? String,
                  let quantity = Decimal(string: rawQuantity)
            else { return nil }
            self = .asNeededTaken(medicationID: medicationID, quantity: quantity, at: date)
        case .symptom:
            guard let symptomID = payload[Key.symptomID] as? String,
                  let severity = payload[Key.severity] as? Int
            else { return nil }
            self = .symptom(symptomID: symptomID, severity: severity, at: date)
        case .mood:
            guard let score = payload[Key.score] as? Int else { return nil }
            self = .mood(score: score, at: date)
        case .requestSnapshot:
            self = .requestSnapshot
        }
    }
}
