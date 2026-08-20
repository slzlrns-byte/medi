import Foundation

/// 하루 중 한 시각. `Date` 가 아니라 시·분만 들고 있어 요일·날짜와 독립적이다.
public struct TimeOfDay: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {

    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// 자정부터의 분. 정렬·비교에 쓴다.
    public var minutesFromMidnight: Int { hour * 60 + minute }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesFromMidnight < rhs.minutesFromMidnight
    }

    /// "08:30"
    public var description: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// "08:30" 형태 문자열에서 되살린다. 형식이 어긋나면 nil.
    public init?(storageKey: String) {
        let parts = storageKey.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m)
        else { return nil }
        self.init(hour: h, minute: m)
    }

    /// 주어진 날짜에 이 시각을 얹은 `Date`.
    ///
    /// 서머타임으로 그 시각이 아예 없는 날이 있다(봄에 02:00~03:00 이 통째로 사라진다).
    /// 그때 `calendar.date(from:)` 은 nil 을 돌려주는데, 예전처럼 `?? day` 로 넘기면
    /// 넘겨받은 자정이 그대로 나가서 02:30 약이 00:00 약이 된다 — 두 시간 반이 조용히 어긋난다.
    /// 없는 시각이면 그 다음으로 실제 존재하는 시각을 찾는다.
    public func date(on day: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0

        if let exact = calendar.date(from: components) { return exact }

        let startOfDay = calendar.startOfDay(for: day)
        if let next = calendar.nextDate(
            after: startOfDay,
            matching: DateComponents(hour: hour, minute: minute),
            matchingPolicy: .nextTime
        ) {
            return next
        }
        return startOfDay
    }
}

/// 요일. `Calendar` 규약과 같게 일요일 = 1.
public enum Weekday: Int, Codable, Sendable, CaseIterable, Comparable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    public var labelKo: String {
        switch self {
        case .sunday: return "일"
        case .monday: return "월"
        case .tuesday: return "화"
        case .wednesday: return "수"
        case .thursday: return "목"
        case .friday: return "금"
        case .saturday: return "토"
        }
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    public static let everyday: Set<Weekday> = Set(Weekday.allCases)

    /// 화면에 늘어놓는 순서. `allCases` 는 Calendar 규약대로 일요일부터라
    /// 그대로 그리면 한국 달력과 어긋난다.
    public static let displayOrderKo: [Weekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday
    ]

    public static func from(date: Date, calendar: Calendar = .current) -> Weekday {
        Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .monday
    }
}

/// 복용 시간대. 아침·점심·저녁·취침 네 개가 기본이고, 나머지는 사용자 정의.
public enum DoseSlot: Hashable, Codable, Sendable {
    case morning
    case noon
    case evening
    case bedtime
    case custom(TimeOfDay)

    public static let presets: [DoseSlot] = [.morning, .noon, .evening, .bedtime]

    public var labelKo: String {
        switch self {
        case .morning: return "아침"
        case .noon: return "점심"
        case .evening: return "저녁"
        case .bedtime: return "취침"
        case .custom(let time): return time.description
        }
    }

    /// 설정을 건드리지 않았을 때의 기본 시각.
    public var defaultTime: TimeOfDay {
        switch self {
        case .morning: return TimeOfDay(hour: 8, minute: 0)
        case .noon: return TimeOfDay(hour: 13, minute: 0)
        case .evening: return TimeOfDay(hour: 19, minute: 0)
        case .bedtime: return TimeOfDay(hour: 22, minute: 30)
        case .custom(let time): return time
        }
    }

    /// 저장·알림 식별자에 쓰는 안정적인 문자열.
    public var storageKey: String {
        switch self {
        case .morning: return "morning"
        case .noon: return "noon"
        case .evening: return "evening"
        case .bedtime: return "bedtime"
        case .custom(let time): return "custom-\(time.description)"
        }
    }

    public init?(storageKey: String) {
        switch storageKey {
        case "morning": self = .morning
        case "noon": self = .noon
        case "evening": self = .evening
        case "bedtime": self = .bedtime
        default:
            let prefix = "custom-"
            guard storageKey.hasPrefix(prefix),
                  let time = TimeOfDay(storageKey: String(storageKey.dropFirst(prefix.count)))
            else { return nil }
            self = .custom(time)
        }
    }

    /// 하루 안에서의 정렬 순서. 사용자 정의 시각도 자연스럽게 끼워 넣는다.
    public var sortKey: Int { defaultTime.minutesFromMidnight }
}

/// 약 하나의 복용 스케줄 한 줄. "아침 8시에 0.5정, 매일" 같은 단위.
public struct Schedule: Identifiable, Hashable, Codable, Sendable {

    public var id: UUID
    public var medicationID: UUID
    public var slot: DoseSlot
    /// 실제 알림이 갈 시각. 기본은 `slot.defaultTime` 이지만 사용자가 옮길 수 있다.
    public var timeOfDay: TimeOfDay
    public var weekdays: Set<Weekday>
    /// 1회 복용 개수. 0.25 단위 소수 허용(반 알 = 0.5).
    public var dosePerIntake: Decimal
    public var startDate: Date?
    public var endDate: Date?

    public init(
        id: UUID = UUID(),
        medicationID: UUID,
        slot: DoseSlot,
        timeOfDay: TimeOfDay? = nil,
        weekdays: Set<Weekday> = Weekday.everyday,
        dosePerIntake: Decimal = 1,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.id = id
        self.medicationID = medicationID
        self.slot = slot
        self.timeOfDay = timeOfDay ?? slot.defaultTime
        self.weekdays = weekdays
        self.dosePerIntake = DecimalQuantity.snapToQuarter(dosePerIntake)
        self.startDate = startDate
        self.endDate = endDate
    }

    /// 그 날짜에 이 스케줄이 살아 있는지.
    ///
    /// 양끝을 **날 단위로** 본다. 시작일은 그 날 0시부터, 종료일은 그 날이 다 갈 때까지다.
    /// 종료일만 날짜로 자르지 않으면, 8월 20일까지인 약이 20일 오후에 이미 끝난 것으로
    /// 취급돼 마지막 날 알림이 하루 일찍 사라진다.
    public func isActive(on day: Date, calendar: Calendar = .current) -> Bool {
        if let start = startDate, day < calendar.startOfDay(for: start) { return false }
        if let end = endDate, calendar.startOfDay(for: day) > calendar.startOfDay(for: end) {
            return false
        }
        return weekdays.contains(Weekday.from(date: day, calendar: calendar))
    }
}

public extension Array where Element == Schedule {
    /// 하루에 예정된 총 개수. 소진 예측의 분모에 들어간다.
    /// 요일이 매일이 아니면 주당 개수를 7로 나눠 하루치로 환산한다.
    func dailyScheduledQuantity() -> Decimal {
        var weeklyTotal: Decimal = 0
        for schedule in self {
            let days = Decimal(schedule.weekdays.count)
            weeklyTotal += schedule.dosePerIntake * days
        }
        guard weeklyTotal > 0 else { return 0 }
        return weeklyTotal / 7
    }
}
