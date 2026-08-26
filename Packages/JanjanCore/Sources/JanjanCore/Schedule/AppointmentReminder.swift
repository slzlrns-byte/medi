import Foundation

/// 다음 진료를 잊지 않게 하는 알림 (2026-08-26 결정).
///
/// 진료를 놓치면 약이 끊긴다. 복약 알림보다 드물지만 놓쳤을 때의 무게는 더 크다.
/// 그래도 **재촉하지 않는다** — 며칠 전 한 번만 조용히 알리고, 그것으로 끝이다.
///
/// 언제·무엇을 알릴지는 여기서 정하고, 실제 예약은 앱 계층이 한다.
public enum AppointmentReminder {

    /// 설정에서 고를 수 있는 값. `off` 는 알리지 않는다.
    public static let off = -1
    public static let allowedLeadDays: [Int] = [off, 0, 1, 2, 7]
    public static let defaultLeadDays = 1

    /// 전날 이전에 알릴 때의 시각. 저녁에 알아야 다음 날 아침을 준비한다.
    public static let eveningTime = TimeOfDay(hour: 19, minute: 0)
    /// 당일에 알릴 때의 시각. 저녁 7시에 "오늘이에요" 는 이미 늦다.
    public static let sameDayTime = TimeOfDay(hour: 8, minute: 0)

    /// 며칠 전이냐에 따라 알릴 시각이 다르다.
    public static func time(forLeadDays leadDays: Int) -> TimeOfDay {
        leadDays <= 0 ? sameDayTime : eveningTime
    }

    public struct Reminder: Identifiable, Hashable, Sendable {

        /// 진료 당일.
        public let visitDate: Date
        /// 알림이 뜰 시각.
        public let fireAt: Date
        public let titleKo: String
        public let bodyKo: String

        /// 알림 식별자. 진료 날짜 하나에 알림 하나다.
        public let id: String

        public init(visitDate: Date, fireAt: Date, titleKo: String, bodyKo: String, id: String) {
            self.visitDate = visitDate
            self.fireAt = fireAt
            self.titleKo = titleKo
            self.bodyKo = bodyKo
            self.id = id
        }
    }

    /// 앞으로 뜰 진료 알림.
    ///
    /// - 지난 진료는 알리지 않는다.
    /// - 알릴 시각이 이미 지났으면 알리지 않는다. 지난 시각으로 예약하면
    ///   iOS 가 그 자리에서 한 번 울려 "내일 진료예요" 가 진료 다음 날 뜬다.
    /// - 같은 날짜가 여러 처방에 적혀 있어도 한 번만 알린다.
    public static func reminders(
        visitDates: [Date],
        leadDays: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> [Reminder] {

        guard leadDays != off, leadDays >= 0 else { return [] }

        let today = calendar.startOfDay(for: now)
        let time = time(forLeadDays: leadDays)

        var seen: Set<String> = []
        var result: [Reminder] = []

        for visit in visitDates.sorted() {
            let visitDay = calendar.startOfDay(for: visit)
            guard visitDay >= today else { continue }

            let key = identifier(for: visitDay, calendar: calendar)
            guard seen.insert(key).inserted else { continue }

            guard let fireDay = calendar.date(byAdding: .day, value: -leadDays, to: visitDay)
            else { continue }

            let fireAt = time.date(on: fireDay, calendar: calendar)
            guard fireAt > now else { continue }

            let remaining = calendar.dateComponents([.day], from: fireDay, to: visitDay).day ?? leadDays

            result.append(
                Reminder(
                    visitDate: visitDay,
                    fireAt: fireAt,
                    titleKo: "다음 진료",
                    bodyKo: bodyKo(daysUntilVisit: remaining),
                    id: key
                )
            )
        }
        return result
    }

    /// "오늘이에요." · "내일이에요." · "모레예요." · "5일 뒤예요."
    /// 한 문장에 한 정보. 느낌표도 재촉도 없다.
    public static func bodyKo(daysUntilVisit days: Int) -> String {
        switch days {
        case ..<0: return "지났어요."
        case 0: return "오늘이에요."
        case 1: return "내일이에요."
        case 2: return "모레예요."
        default: return "\(days)일 뒤예요."
        }
    }

    /// 설정 화면의 선택지 라벨.
    public static func leadLabelKo(forDays days: Int) -> String {
        switch days {
        case off: return "안 함"
        case 0: return "당일 아침"
        case 1: return "하루 전 저녁"
        case 2: return "이틀 전 저녁"
        default: return "\(days)일 전 저녁"
        }
    }

    /// 알림 식별자. `visit-20260830` 처럼 날짜 하나에 하나.
    public static func identifier(for day: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(
            format: "visit-%04d%02d%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
    }
}
