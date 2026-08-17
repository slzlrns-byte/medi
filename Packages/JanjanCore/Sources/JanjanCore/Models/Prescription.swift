import Foundation

/// 한 번의 진료로 받아 온 처방 묶음. 리포트에서 "약이 바뀐 지점" 마커로도 쓴다.
public struct Prescription: Identifiable, Hashable, Codable, Sendable {

    public var id: UUID
    /// 진료 받은 날.
    public var visitDate: Date
    /// 처방 일수. 이 값 × 하루 예정 개수 = 보충 제안 개수.
    public var daysSupplied: Int
    /// 다음 진료 예정일. 부족 알림의 기준이 된다.
    public var nextVisitDate: Date?
    public var clinicNote: String
    /// 이 처방으로 보충한 약 목록.
    public var medicationIDs: [UUID]

    public init(
        id: UUID = UUID(),
        visitDate: Date,
        daysSupplied: Int,
        nextVisitDate: Date? = nil,
        clinicNote: String = "",
        medicationIDs: [UUID] = []
    ) {
        self.id = id
        self.visitDate = visitDate
        self.daysSupplied = max(0, daysSupplied)
        self.nextVisitDate = nextVisitDate
        self.clinicNote = clinicNote
        self.medicationIDs = medicationIDs
    }

    /// 처방일수와 하루 예정 개수로 보충 개수를 제안한다. 사용자가 고칠 수 있는 초안일 뿐이다.
    public func suggestedRefillQuantity(dailyScheduledQuantity: Decimal) -> Decimal {
        DecimalQuantity.snapToQuarter(Decimal(daysSupplied) * dailyScheduledQuantity)
    }

    /// 오늘 기준 다음 진료까지 남은 날. 진료일이 없으면 nil.
    public func daysUntilNextVisit(from date: Date, calendar: Calendar = .current) -> Int? {
        guard let next = nextVisitDate else { return nil }
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: next)
        return calendar.dateComponents([.day], from: start, to: end).day
    }
}
