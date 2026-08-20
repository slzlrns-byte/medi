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
        /// 이미 기록이 끝났는지.
        public let isCompleted: Bool

        public init(
            slotKey: String,
            labelKo: String,
            timeText: String,
            medicationNames: [String],
            isCompleted: Bool
        ) {
            self.slotKey = slotKey
            self.labelKo = labelKo
            self.timeText = timeText
            self.medicationNames = medicationNames
            self.isCompleted = isCompleted
        }

        public var summaryKo: String {
            if medicationNames.isEmpty { return "예정된 약 없음" }
            return "\(medicationNames.count)종"
        }
    }

    public let generatedAt: Date
    /// "8/17"
    public let dateText: String
    public let slots: [SlotLine]
    /// 오늘 아직 기록하지 않은 약 개수. 컴플리케이션에 그대로 쓴다.
    public let remainingCountToday: Int
    /// 워치 앱은 Pro 기능이다(무료/Pro 경계 결정). **판단은 폰이 한다.**
    /// 워치에 StoreKit 을 올리지 않는 이유는 이 앱의 원칙 그대로다 —
    /// 워치는 아무것도 계산하지 않고 받은 그림만 그린다.
    public let isPro: Bool

    public init(
        generatedAt: Date = Date(),
        dateText: String,
        slots: [SlotLine],
        remainingCountToday: Int,
        isPro: Bool = true
    ) {
        self.generatedAt = generatedAt
        self.dateText = dateText
        self.slots = slots
        self.remainingCountToday = remainingCountToday
        self.isPro = isPro
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAt, dateText, slots, remainingCountToday, isPro
    }

    /// 키가 없던 시절의 스냅샷이 남아 있어도 되살아나게 한다.
    /// 워치에 마지막으로 건너간 그림은 앱을 지우기 전까지 그대로 남아 있다.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        dateText = try container.decode(String.self, forKey: .dateText)
        slots = try container.decode([SlotLine].self, forKey: .slots)
        remainingCountToday = try container.decode(Int.self, forKey: .remainingCountToday)
        isPro = try container.decodeIfPresent(Bool.self, forKey: .isPro) ?? true
    }

    public static let placeholder = WatchSnapshot(
        dateText: "—",
        slots: [],
        remainingCountToday: 0
    )

    /// 구독하지 않은 사용자의 워치에 보내는 그림. 오늘 일정은 담기지 않는다.
    public static func locked(dateText: String, generatedAt: Date = Date()) -> WatchSnapshot {
        WatchSnapshot(
            generatedAt: generatedAt,
            dateText: dateText,
            slots: [],
            remainingCountToday: 0,
            isPro: false
        )
    }
}

/// 워치 → 아이폰으로 흘려보내는 메시지.
///
/// WatchConnectivity 는 `[String: Any]` 만 받으므로 딕셔너리로 굽고 되살리는 코드를
/// 여기 한 곳에 모아 둔다. 양쪽 앱이 같은 타입을 쓰니 키가 어긋날 수 없다.
public enum WatchMessage: Hashable, Sendable {

    case doseAction(medicationIDs: [UUID], slotKey: String, action: DoseAction)
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
        public static let symptomID = "symptomID"
        public static let severity = "severity"
        public static let score = "score"
        public static let timestamp = "timestamp"
        public static let snapshot = "snapshot"
    }

    private enum Kind: String {
        case doseAction
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
