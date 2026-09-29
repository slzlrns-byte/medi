import Foundation

/// 복용 사건 하나. 재고 계산과 복약률의 유일한 원천이다(설계 5절·13절).
///
/// "미기록" 도 하나의 상태로 저장한다. 아무 행도 없는 것과, 사용자가 응답하지 않아
/// 모르는 것은 다르다. 미기록은 재고를 차감하지 않지만 복약률 분모에는 들어간다.
public struct DoseEvent: Identifiable, Hashable, Codable, Sendable {

    public enum Status: String, Codable, Sendable, CaseIterable {
        case taken
        case skipped
        case unrecorded

        public var labelKo: String {
            switch self {
            case .taken: return "복용함"
            case .skipped: return "건너뜀"
            case .unrecorded: return "미기록"
            }
        }

        public var labelEn: String {
            switch self {
            case .taken: return "Taken"
            case .skipped: return "Skipped"
            case .unrecorded: return "Unrecorded"
            }
        }

        public func label(_ language: JanjanLanguage) -> String {
            language == .english ? labelEn : labelKo
        }

        /// 재고에서 실제로 빠지는 상태인가. 복용함만 차감한다.
        public var consumesStock: Bool { self == .taken }
    }

    /// 어디서 기록됐는지. 통계·디버깅용이며 재고 계산에는 영향이 없다.
    public enum Source: String, Codable, Sendable, CaseIterable {
        case phone
        case watch
        case notificationAction
        case widget
        case siri
        /// **사용자가 답한 것이 아니다.** 시각이 지나도록 아무 답이 없던
        /// 시간대를 앱이 미기록으로 채운 것이다(2026-09-19 결정).
        ///
        /// 이것이 없으면 복약률의 분모가 "답한 횟수" 가 되어, 앱을 가끔만
        /// 여는 사람일수록 숫자가 더 높게 나오는 역설이 생긴다 - 28일 중
        /// 14일만 열어 그때마다 복용함을 눌렀으면 100% 로 찍힌다.
        ///
        /// 사용자가 직접 고른 "기억나지 않아요" 와는 구별해야 한다. 그쪽은
        /// 답이므로 다시 묻지 않고, 이쪽은 답이 아니므로 계속 물어본다.
        case automatic

        public var labelKo: String {
            switch self {
            case .phone: return "아이폰"
            case .watch: return "애플워치"
            case .notificationAction: return "알림"
            case .widget: return "위젯"
            case .siri: return "시리"
            case .automatic: return "자동"
            }
        }

        public var labelEn: String {
            switch self {
            case .phone: return "iPhone"
            case .watch: return "Apple Watch"
            case .notificationAction: return "Notification"
            case .widget: return "Widget"
            case .siri: return "Siri"
            case .automatic: return "Automatic"
            }
        }

        public func label(_ language: JanjanLanguage) -> String {
            language == .english ? labelEn : labelKo
        }
    }

    /// 정기 복용 예정분인지, 필요시(PRN) 복용인지.
    /// 복약률은 정기 예정분만 센다. 필요시 약은 안 먹은 게 정상이라 분모에 넣으면 안 된다.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case scheduled
        case asNeeded
    }

    public var id: UUID
    public var medicationID: UUID
    /// 예정 시각. 필요시 약이면 "복용을 시도한 시각" 으로 같이 쓴다.
    public var scheduledAt: Date
    /// 실제 복용 시각. 늦게 먹고 나중에 고쳐 넣을 수 있다.
    public var actualAt: Date?
    public var status: Status
    /// 건너뛴 이유(선택). 판단하지 않고 사용자의 말 그대로 담는다.
    public var skipReason: String?
    public var source: Source
    /// 이 사건으로 소비된 개수. 반 알이면 0.5.
    public var quantity: Decimal
    public var kind: Kind
    /// 어느 시간대의 예정분이었는지. 필요시 약이면 nil.
    public var slotKey: String?

    public init(
        id: UUID = UUID(),
        medicationID: UUID,
        scheduledAt: Date,
        actualAt: Date? = nil,
        status: Status = .unrecorded,
        skipReason: String? = nil,
        source: Source = .phone,
        quantity: Decimal = 1,
        kind: Kind = .scheduled,
        slotKey: String? = nil
    ) {
        self.id = id
        self.medicationID = medicationID
        self.scheduledAt = scheduledAt
        self.actualAt = actualAt
        self.status = status
        self.skipReason = skipReason
        self.source = source
        self.quantity = DecimalQuantity.snapToQuarter(quantity)
        self.kind = kind
        self.slotKey = slotKey
    }

    /// 재고·통계에서 이 사건이 "일어난 시각" 으로 보는 값.
    /// 실제 복용 시각이 있으면 그것을, 없으면 예정 시각을 쓴다.
    public var effectiveDate: Date { actualAt ?? scheduledAt }

    /// 재고에서 빠지는 개수. 복용함이 아니면 0.
    public var consumedQuantity: Decimal {
        status.consumesStock ? quantity : 0
    }
}
