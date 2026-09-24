import Foundation

/// 하루 한 개의 기분 체크인. 2층 구조라 1층(기분 하나)만 채워도 완전한 기록이다.
///
/// 어느 필드가 비어 있어도 정상이다. 앱은 빈 칸을 재촉하지 않는다(설계 09절).
public struct CheckIn: Identifiable, Hashable, Codable, Sendable {

    /// −3 ~ +3 의 7단계. 값과 라벨은 항상 함께 보여 준다.
    public struct Mood: Hashable, Codable, Sendable, Comparable {

        public static let range: ClosedRange<Int> = -3...3

        public static let labelsKo: [String] = [
            "매우 힘듦", "힘듦", "조금 힘듦", "그저 그럼", "조금 괜찮음", "괜찮음", "좋음"
        ]

        /// 영어도 같은 결: 평가하는 말(bad/great) 대신 무게를 말한다.
        public static let labelsEn: [String] = [
            "Very hard", "Hard", "A bit hard", "So-so", "A bit okay", "Okay", "Good"
        ]

        public var score: Int

        public init(_ score: Int) {
            self.score = min(max(score, Mood.range.lowerBound), Mood.range.upperBound)
        }

        /// 0(가장 힘듦) ~ 6(가장 좋음) 의 인덱스. 색·라벨 배열과 짝을 맞출 때 쓴다.
        public var index: Int { score - Mood.range.lowerBound }

        public var labelKo: String { Mood.labelsKo[index] }
        public var labelEn: String { Mood.labelsEn[index] }

        public func label(_ language: JanjanLanguage) -> String {
            language == .english ? labelEn : labelKo
        }

        public static func < (lhs: Mood, rhs: Mood) -> Bool { lhs.score < rhs.score }
    }

    /// 수면의 질. 1~5 대신 세 단계로만 물어 부담을 줄인다.
    public enum SleepQuality: String, Codable, Sendable, CaseIterable {
        case poor
        case fair
        case good

        public var labelKo: String {
            switch self {
            case .poor: return "잘 못 잠"
            case .fair: return "그럭저럭"
            case .good: return "잘 잠"
            }
        }

        public var labelEn: String {
            switch self {
            case .poor: return "Slept poorly"
            case .fair: return "So-so"
            case .good: return "Slept well"
            }
        }

        public func label(_ language: JanjanLanguage) -> String {
            language == .english ? labelEn : labelKo
        }
    }

    public var id: UUID
    /// 그날 하루를 가리키는 날짜. 시각 부분은 자정으로 맞춰 저장한다.
    public var date: Date
    public var mood: Mood
    /// 1~5. 안 고르면 nil.
    public var energy: Int?
    /// 1~5. 안 고르면 nil.
    public var anxiety: Int?
    /// `emotion_words.json` 의 id 목록 + 사용자가 직접 추가한 단어.
    public var emotionWords: [String]
    public var sleepMinutes: Int?
    public var sleepQuality: SleepQuality?
    public var dreamed: Bool?
    // 꿈 3척도 (강점 결정서 D15). SSRI 계열의 생생한 꿈은 부작용 축에서 함께
    // 보는 것이 이 앱의 차별점이라, 척도만 받고 해석은 하지 않는다.
    /// 얼마나 생생했는지. 1~3, 안 고르면 nil.
    public var dreamVividness: Int?
    /// 악몽이었는지. 안 고르면 nil.
    public var nightmare: Bool?
    /// 얼마나 기억나는지. 1~3, 안 고르면 nil.
    public var dreamRecall: Int?
    /// 꿈 한 줄 메모.
    public var dreamNote: String?
    /// 활동 태그. 외출·운동·사람·술·카페인 등.
    public var activities: [String]
    /// 1층에서 조용히 펼쳐지는 한 줄.
    public var note: String?
    /// 2층의 길이 제한 없는 글.
    public var longText: String?
    /// 그날 보여 준 질문 카드 id.
    public var questionCardID: String?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        date: Date,
        mood: Mood,
        energy: Int? = nil,
        anxiety: Int? = nil,
        emotionWords: [String] = [],
        sleepMinutes: Int? = nil,
        sleepQuality: SleepQuality? = nil,
        dreamed: Bool? = nil,
        dreamVividness: Int? = nil,
        nightmare: Bool? = nil,
        dreamRecall: Int? = nil,
        dreamNote: String? = nil,
        activities: [String] = [],
        note: String? = nil,
        longText: String? = nil,
        questionCardID: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.mood = mood
        self.energy = energy.map { min(max($0, 1), 5) }
        self.anxiety = anxiety.map { min(max($0, 1), 5) }
        self.emotionWords = emotionWords
        self.sleepMinutes = sleepMinutes.map { max(0, $0) }
        self.sleepQuality = sleepQuality
        self.dreamed = dreamed
        self.dreamVividness = dreamVividness.map { min(max($0, 1), 3) }
        self.nightmare = nightmare
        self.dreamRecall = dreamRecall.map { min(max($0, 1), 3) }
        self.dreamNote = dreamNote
        self.activities = activities
        self.note = note
        self.longText = longText
        self.questionCardID = questionCardID
        self.updatedAt = updatedAt
    }

    /// 같은 날의 체크인이 여러 줄이면 가장 나중에 손댄 것만 남긴다.
    ///
    /// 하루 1개는 CheckInRecorder 가 지키지만, 오프라인 두 기기가 각자 적은 뒤
    /// iCloud 로 만나면 같은 날 두 줄이 생길 수 있다. 리포트가 그대로 세면
    /// "꿈을 기록한 날" 같은 일수가 부풀어 거짓말이 된다(QA 2026-09-10).
    /// MonthWave 와 같은 규칙: updatedAt 이 나중인 쪽, 같으면 id 가 큰 쪽.
    public static func collapsedByDay(
        _ checkIns: [CheckIn],
        calendar: Calendar = .current
    ) -> [CheckIn] {
        var latest: [Date: CheckIn] = [:]
        for checkIn in checkIns {
            let day = calendar.startOfDay(for: checkIn.date)
            if let kept = latest[day], isLater(kept, than: checkIn) { continue }
            latest[day] = checkIn
        }
        return latest.values.sorted { $0.date < $1.date }
    }

    private static func isLater(_ lhs: CheckIn, than rhs: CheckIn) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    /// 1층만 채운 최소 기록인지. 리포트에서 "가볍게 남긴 날" 로 구분한다.
    public var isQuickOnly: Bool {
        energy == nil && anxiety == nil && emotionWords.isEmpty
            && sleepMinutes == nil && activities.isEmpty
            && (longText?.isEmpty ?? true)
    }

    /// "7시간 20분"
    public var sleepDurationTextKo: String? {
        guard let minutes = sleepMinutes else { return nil }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)분" }
        if rest == 0 { return "\(hours)시간" }
        return "\(hours)시간 \(rest)분"
    }
}
