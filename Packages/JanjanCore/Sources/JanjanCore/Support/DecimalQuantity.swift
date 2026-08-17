import Foundation

/// 개수 계산용 Decimal 도우미.
///
/// 잔여 개수는 절대 Double 로 다루지 않는다. 0.5정 + 0.25정 같은 값을 더할 때
/// 부동소수 오차가 쌓이면 "6개 남음" 이 "5.999999개" 가 되어 사용자에게 그대로 보인다.
public enum DecimalQuantity {

    /// 허용 최소 단위. 반 알(0.5)과 그 절반(0.25)까지만 인정한다.
    public static let step = Decimal(string: "0.25") ?? 0

    /// 가장 가까운 0.25 배수로 맞춘다. 음수는 0 으로 자르지 않고 그대로 둔다.
    public static func snapToQuarter(_ value: Decimal) -> Decimal {
        guard step > 0 else { return value }
        var quotient = value / step
        var rounded = Decimal()
        NSDecimalRound(&rounded, &quotient, 0, .plain)
        return rounded * step
    }

    /// 0.25 배수인지.
    public static func isQuarterAligned(_ value: Decimal) -> Bool {
        snapToQuarter(value) == value
    }

    /// 소수점 아래 `scale` 자리에서 반올림. 나눗셈 결과의 꼬리 오차를 털어낸다.
    public static func round(_ value: Decimal, scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, mode)
        return result
    }

    /// 사람이 읽는 문자열. 정수면 "6", 아니면 "5.5" 처럼 꼬리 0 을 뗀다.
    public static func display(_ value: Decimal) -> String {
        let rounded = round(value, scale: 2)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: rounded as NSDecimalNumber) ?? "\(rounded)"
    }

    /// Decimal → Int 내림. 소진 일수처럼 "며칠" 로 말해야 할 때.
    public static func floorToInt(_ value: Decimal) -> Int {
        let rounded = round(value, scale: 0, mode: .down)
        return (rounded as NSDecimalNumber).intValue
    }

    /// Decimal → Int 올림. "며칠 모자람" 처럼 모자란 쪽을 넉넉히 볼 때.
    public static func ceilToInt(_ value: Decimal) -> Int {
        let rounded = round(value, scale: 0, mode: .up)
        return (rounded as NSDecimalNumber).intValue
    }
}
