import Foundation

/// 안전 카드를 언제 내밀지 정한다 (2026-08-17 결정).
///
/// 두 가지 경우다.
///   1. '자해·자살 생각' 처럼 카탈로그에 안전 항목으로 표시된 증상을 저장했을 때
///   2. 기분 '매우 힘듦(−3)' 이 3일 연속일 때
///
/// **이 판단은 경고가 아니다.** 앱은 진단하지도, 막지도, 재촉하지도 않는다.
/// 기록은 방해 없이 그대로 저장되고, 카드는 연락처를 조용히 내밀 뿐이며 닫을 수 있다.
public enum SafetyTrigger {

    /// 이 점수 이하가 이어지면 센다.
    public static let lowMoodScore = -3
    /// 며칠 이어져야 카드를 내미는가.
    public static let lowMoodRunLength = 3

    /// 카드를 내미는 이유. 화면은 이유에 따라 문구를 바꾸지 않는다 —
    /// 어느 쪽이든 같은 한 문장과 같은 연락처를 보여 준다.
    /// 이유를 남기는 것은 나중에 이 규칙을 다시 볼 때를 위해서다.
    public enum Reason: Hashable, Sendable {
        case safetySymptom(symptomID: String)
        case lowMoodRun(days: Int)
    }

    // MARK: - 증상

    /// 방금 저장한 증상이 안전 항목인가.
    public static func reason(
        forSavedSymptomID symptomID: String,
        in catalog: SymptomCatalog = Catalogs.symptoms
    ) -> Reason? {
        guard catalog.symptom(id: symptomID)?.isSafetyItem == true else { return nil }
        return .safetySymptom(symptomID: symptomID)
    }

    // MARK: - 이어지는 기분

    /// `day` 부터 거슬러 올라가며 '매우 힘듦' 이 며칠 이어졌는지 센다.
    ///
    /// 기록이 없는 날에서 멈춘다. 안 적은 날을 힘들었던 날로 세면,
    /// 며칠 앱을 열지 않았다는 이유만으로 카드가 올라온다.
    public static func consecutiveLowMoodDays(
        checkIns: [CheckIn],
        endingAt day: Date,
        calendar: Calendar = .current
    ) -> Int {

        // 하루에 한 장이 원칙이지만, 어긋난 값이 들어와도 가장 나중에 고친 것을 진실로 본다.
        var byDay: [Date: CheckIn] = [:]
        for checkIn in checkIns {
            let key = calendar.startOfDay(for: checkIn.date)
            if let existing = byDay[key], existing.updatedAt >= checkIn.updatedAt { continue }
            byDay[key] = checkIn
        }

        var run = 0
        var cursor = calendar.startOfDay(for: day)

        while let checkIn = byDay[cursor], checkIn.mood.score <= lowMoodScore {
            run += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return run
    }

    /// 이어지는 기분 때문에 카드를 내밀어야 하는가.
    public static func reason(
        forCheckIns checkIns: [CheckIn],
        endingAt day: Date,
        calendar: Calendar = .current
    ) -> Reason? {
        let run = consecutiveLowMoodDays(checkIns: checkIns, endingAt: day, calendar: calendar)
        guard run >= lowMoodRunLength else { return nil }
        return .lowMoodRun(days: run)
    }
}
