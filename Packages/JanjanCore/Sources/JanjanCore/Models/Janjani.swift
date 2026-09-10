import Foundation

/// 잔잔이(수달)의 하루. 시각만으로 정해지는 순수 규칙이라 여기 둔다.
///
/// 잔잔이는 굶지 않고, 아프지 않고, 떠나지 않는다. 여기 있는 것은 '지금 무엇을
/// 하고 있는가' 뿐이다 — 아침엔 헤엄치고, 낮엔 떠 있고, 밤엔 잔다.
public enum JanjaniPhase: String, Sendable, CaseIterable {

    case morning
    case day
    case night

    /// 5~10시 아침, 11~18시 낮, 나머지는 밤.
    public static func phase(forHour hour: Int) -> JanjaniPhase {
        switch hour {
        case 5...10: return .morning
        case 11...18: return .day
        default: return .night
        }
    }

    public static func phase(at moment: Date, calendar: Calendar = .current) -> JanjaniPhase {
        phase(forHour: calendar.component(.hour, from: moment))
    }
}

/// 물가에 쌓이는 것들의 셈.
///
/// **하루라도 무언가를 적은 날**의 수다. 체크인이든 복약이든 하나면 그 날은
/// 셌고, 같은 날 여러 번 적어도 하루다. 거른 날은 아무것도 바꾸지 않는다 —
/// 이 수는 줄어들 방법이 없다. 화면은 이 수만큼 조약돌·물풀을 놓을 뿐,
/// 숫자를 보여 주지는 않는다.
public enum JanjaniKeepsakes {

    public static func recordedDayCount(
        checkIns: [CheckIn],
        doseEvents: [DoseEvent],
        calendar: Calendar = .current
    ) -> Int {
        var days = Set<Date>()
        for checkIn in checkIns {
            days.insert(calendar.startOfDay(for: checkIn.date))
        }
        // 미기록은 '답하지 않음' 이라 세지 않는다. 복용함·건너뜀은 둘 다 답이다.
        for event in doseEvents where event.status != .unrecorded {
            days.insert(calendar.startOfDay(for: event.effectiveDate))
        }
        return days.count
    }
}
