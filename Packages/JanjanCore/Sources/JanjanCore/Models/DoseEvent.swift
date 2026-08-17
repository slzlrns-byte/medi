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

        /// 재고에서 실제로 빠지는 상태인가. 복용함만 차감한다.
        public var consumesStock: Bool { self == .taken }
    }

    /// 어디서 기록됐는지. 통계·디버깅용이며 재고 계산에는 영향이 없다.
    public enum Source: String, Codable, Sendable, CaseIterable {
        case phone
        case watch
        case notificationAction

        public var labelKo: String {
            switch self {
            case .phone: return "아이폰"
            case .watch: return "애플워치"
            case .notificationAction: return "알림"
            }
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
