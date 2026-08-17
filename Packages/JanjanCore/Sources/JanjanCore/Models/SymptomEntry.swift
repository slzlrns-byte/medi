import Foundation

/// 증상 기록 한 건. 하루에 여러 건 남길 수 있다.
///
/// 진단하지 않는다. 세기 0–10 과 사용자가 고른 일상어 항목만 담는다(설계 12절).
public struct SymptomEntry: Identifiable, Hashable, Codable, Sendable {

    public enum Source: String, Codable, Sendable, CaseIterable {
        case phone
        case watch
        case notificationAction
    }

    public static let severityRange: ClosedRange<Int> = 0...10

    public var id: UUID
    /// `symptom_catalog.json` 의 id, 또는 사용자가 추가한 항목의 id.
    public var symptomID: String
    /// 0–10 공통 세기.
    public var severity: Int
    public var startedAt: Date
    public var durationMinutes: Int?
    /// 촉발 상황 태그.
    public var contextTags: [String]
    /// 부작용 의심일 때 연결하는 약.
    public var relatedMedicationID: UUID?
    public var note: String?
    public var source: Source

    public init(
        id: UUID = UUID(),
        symptomID: String,
        severity: Int,
        startedAt: Date,
        durationMinutes: Int? = nil,
        contextTags: [String] = [],
        relatedMedicationID: UUID? = nil,
        note: String? = nil,
        source: Source = .phone
    ) {
        self.id = id
        self.symptomID = symptomID
        self.severity = min(max(severity, SymptomEntry.severityRange.lowerBound),
                            SymptomEntry.severityRange.upperBound)
        self.startedAt = startedAt
        self.durationMinutes = durationMinutes.map { max(0, $0) }
        self.contextTags = contextTags
        self.relatedMedicationID = relatedMedicationID
        self.note = note
        self.source = source
    }

    /// 이 기록을 저장할 때 안전 카드를 띄워야 하는지.
    /// 카탈로그의 `safety: true` 항목이면 참. 경고가 아니라 연락처를 조용히 내미는 용도다.
    public func needsSafetyCard(catalog: SymptomCatalog) -> Bool {
        catalog.symptom(id: symptomID)?.safety == true
    }
}
