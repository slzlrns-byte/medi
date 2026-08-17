import Foundation
import XCTest
@testable import JanjanCore

/// 테스트 전용 달력. 러너의 시간대(UTC)와 개발자 기기(KST)에서 결과가 달라지지 않도록
/// 항상 UTC 그레고리력을 쓴다.
enum Fixed {

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        let components = DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: 0
        )
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    static let medA = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001") ?? UUID()
    static let medB = UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000002") ?? UUID()

    /// 설계 문서 예시용 데이터: 8/1 에 28정 보충, 하루 1정.
    static func workedExampleStock() -> [StockEvent] {
        [.refill(medicationID: medA, quantity: 28, at: date(2026, 8, 1, 9, 0))]
    }

    /// 8/1 ~ 8/17 의 17건. 14 복용 · 2 건너뜀 · 1 미기록.
    static func workedExampleDoses() -> [DoseEvent] {
        var events: [DoseEvent] = []
        for day in 1...17 {
            let scheduled = date(2026, 8, day, 21, 0)
            let status: DoseEvent.Status
            switch day {
            case 1...14: status = .taken
            case 15, 16: status = .skipped
            default: status = .unrecorded
            }
            events.append(
                DoseEvent(
                    medicationID: medA,
                    scheduledAt: scheduled,
                    actualAt: status == .taken ? scheduled : nil,
                    status: status,
                    quantity: 1,
                    kind: .scheduled,
                    slotKey: DoseSlot.bedtime.storageKey
                )
            )
        }
        return events
    }

    static func decimal(_ text: String) -> Decimal {
        Decimal(string: text) ?? 0
    }
}
