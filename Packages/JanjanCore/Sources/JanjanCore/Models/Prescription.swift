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

    /// 다음 진료 **일정만** 담은 기록인지. 다녀온 진료로 세지 않는다.
    ///
    /// 오늘 탭의 "다음 진료" 칩이 만드는 기록이 이 모양이다 - 약도 처방일수도
    /// 메모도 없고, `visitDate` 와 `nextVisitDate` 가 같은 날짜 하나다.
    ///
    /// **비어 있다는 것만으로 판정하지 않는다**(사용자 지적 2026-09-22).
    /// 진료 기록 화면에서 저장한 진료도, 약을 고르지 않고 처방일수와 메모를
    /// 비우면 똑같이 비어 보인다. 예전 규칙은 그것까지 가짜로 보아서 사용자가
    /// 직접 남긴 진료가 지난 진료 기록·리포트·"진료 이후 약 변경" 에서 통째로
    /// 사라졌다. 일정만 담은 기록은 **두 날짜가 같다**는 것으로 갈라낸다.
    public var isScheduleOnly: Bool {
        guard medicationIDs.isEmpty,
              daysSupplied == 0,
              clinicNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        guard let next = nextVisitDate else { return false }
        return next == visitDate
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
