import Foundation

/// 재고를 직접 움직이는 사건. 보충과 정정 두 가지뿐이다.
///
/// 소비(consumption)는 여기에 저장하지 않는다. 복용은 `DoseEvent` 에서 파생되며,
/// 같은 사실을 두 곳에 적으면 반드시 어긋난다(설계 5절).
public struct StockEvent: Identifiable, Hashable, Codable, Sendable {

    public enum Kind: Hashable, Codable, Sendable {
        /// 처방을 받아와 N개를 더한다.
        case refill(quantity: Decimal)
        /// 실제로 세어 보니 N개였다. 이 시점이 새 기준점이 된다.
        case correction(setTo: Decimal)

        public var labelKo: String {
            switch self {
            case .refill: return "보충"
            case .correction: return "직접 정정"
            }
        }
    }

    public var id: UUID
    public var medicationID: UUID
    public var kind: Kind
    public var occurredAt: Date
    /// 한 번의 처방으로 여러 약을 함께 보충했을 때 묶는 ID.
    public var prescriptionID: UUID?
    public var note: String?

    public init(
        id: UUID = UUID(),
        medicationID: UUID,
        kind: Kind,
        occurredAt: Date,
        prescriptionID: UUID? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.medicationID = medicationID
        self.kind = kind
        self.occurredAt = occurredAt
        self.prescriptionID = prescriptionID
        self.note = note
    }

    public static func refill(
        medicationID: UUID,
        quantity: Decimal,
        at date: Date,
        prescriptionID: UUID? = nil
    ) -> StockEvent {
        StockEvent(
            medicationID: medicationID,
            kind: .refill(quantity: DecimalQuantity.snapToQuarter(quantity)),
            occurredAt: date,
            prescriptionID: prescriptionID
        )
    }

    public static func correction(
        medicationID: UUID,
        setTo: Decimal,
        at date: Date,
        note: String? = nil
    ) -> StockEvent {
        StockEvent(
            medicationID: medicationID,
            kind: .correction(setTo: DecimalQuantity.snapToQuarter(setTo)),
            occurredAt: date,
            note: note
        )
    }

    public var isCorrection: Bool {
        if case .correction = kind { return true }
        return false
    }
}
