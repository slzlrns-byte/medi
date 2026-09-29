import Foundation

/// 별점 창(`requestReview`)을 청하는 조건.
///
/// 시스템 창은 애플이 한 번 더 거르고 1년에 세 번이 상한이지만, 우리는
/// **평생 한 번만** 청한다 - 조르지 않는다. 그래서 문턱이 곧 전부다:
/// 서로 다른 며칠을 기록한 사람에게 청할지.
///
/// 문턱은 두 단계다(사용자 결정 2026-09-29).
///   · **출시 직후**에는 낮춘다. 아직 쓰는 사람이 적어 리뷰 한 줄이 무겁고,
///     리뷰 없는 앱은 스토어에서 잘 안 보인다.
///   · `launchWindowEnd` 가 지나면 저절로 원래 문턱으로 돌아간다. 빌드를
///     다시 내지 않아도 되도록 날짜로 자른다.
public enum ReviewRequestPolicy {

    /// 출시 직후 창이 닫히는 날(한국 시각 자정). 이 날까지는 `launchWindowDays`,
    /// 그 뒤로는 `steadyDays` 를 쓴다.
    public static let launchWindowEnd: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 12
        components.day = 31
        components.hour = 23
        components.minute = 59
        components.second = 59
        components.timeZone = TimeZone(identifier: "Asia/Seoul")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        // 구성 요소가 전부 상수라 실패할 수 없지만, 강제 해제는 두지 않는다.
        return calendar.date(from: components) ?? .distantPast
    }()

    /// 출시 직후의 문턱. 사흘이면 "깔아 보고 지웠다" 는 아니고, 알림을 받아
    /// 아침·저녁을 몇 번 눌러 본 사람이다.
    public static let launchWindowDays = 3

    /// 평소의 문턱. 한 주를 채운 사람이면 이 앱이 자기 것인지 안다.
    public static let steadyDays = 7

    /// `asOf` 시점에 청하려면 서로 다른 며칠을 기록했어야 하는지.
    public static func requiredRecordedDays(asOf date: Date) -> Int {
        date <= launchWindowEnd ? launchWindowDays : steadyDays
    }

    /// 청할 조건이 됐는지. `recordedDays` 는 복용 기록이 있는 서로 다른 날의 수다.
    public static func shouldAsk(recordedDays: Int, asOf date: Date) -> Bool {
        recordedDays >= requiredRecordedDays(asOf: date)
    }
}
