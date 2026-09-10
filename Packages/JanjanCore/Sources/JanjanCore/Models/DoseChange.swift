import Foundation

/// 용량이 바뀐 사건. **입력만 받는다** (강점 결정서 D12) — 계산도 권고도 없다.
///
/// "9/3 에스시탈로프람 10mg → 15mg" 이 리포트의 축이 된다. 언제 무엇이
/// 바뀌었는지를 기분·부작용·꿈 옆에 놓아 주면 해석은 진료실에서 사람이 한다.
public struct DoseChange: Identifiable, Hashable, Codable, Sendable {

    public var id: UUID
    public var medicationID: UUID
    /// 바뀐 날.
    public var changedAt: Date
    /// 바꾸기 전 표기. "10mg". 처음 적는 경우 비어 있을 수 있다.
    public var fromText: String
    /// 바꾼 뒤 표기. "15mg".
    public var toText: String
    /// 덧붙일 말 (선택).
    public var note: String?

    public init(
        id: UUID = UUID(),
        medicationID: UUID,
        changedAt: Date,
        fromText: String,
        toText: String,
        note: String? = nil
    ) {
        self.id = id
        self.medicationID = medicationID
        self.changedAt = changedAt
        self.fromText = fromText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.toText = toText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = note
    }

    /// "10mg → 15mg". 이전 표기가 없으면 새 표기만.
    public var arrowTextKo: String {
        fromText.isEmpty ? toText : "\(fromText) → \(toText)"
    }
}
