import Foundation

/// 약에 딸린 한 줄 메모 (2026-08-26 결정).
///
/// **바깥에서 들여온 약 정보가 아니라 사용자 자신의 말이다.** 진료실에서 들은 것,
/// 다음에 여쭤볼 것. 앱은 이 문장을 고치지도 해석하지도 않고 그대로 담았다가 그대로 꺼낸다.
///
/// 식약처 이상반응 원문을 싣지 않기로 한 자리에 이것이 들어간다. 목록을 펼쳐 보이는 대신,
/// 담당의가 이미 골라 준 몇 줄을 잊지 않게 붙들어 둔다.
public struct MedicationNote: Identifiable, Hashable, Codable, Sendable {

    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {

        public var id: String { rawValue }

        /// 진료에서 들은 것. "처음 며칠 졸릴 수 있다고 하심"
        case heardFromDoctor
        /// 다음 진료에서 여쭤볼 것. "아침에 더 졸린데 시간을 옮겨도 되는지"
        case questionForDoctor

        public var labelKo: String {
            switch self {
            case .heardFromDoctor: return "들은 것"
            case .questionForDoctor: return "여쭤볼 것"
            }
        }

        /// 입력칸 위에 붙는 제목.
        public var titleKo: String {
            switch self {
            case .heardFromDoctor: return "선생님이 말씀하신 것"
            case .questionForDoctor: return "다음에 여쭤볼 것"
            }
        }

        public var placeholderKo: String {
            switch self {
            case .heardFromDoctor: return "예: 처음 며칠 졸릴 수 있다고 하심"
            case .questionForDoctor: return "예: 아침에 더 졸린데 시간을 옮겨도 되는지"
            }
        }
    }

    public var id: UUID
    public var medicationID: UUID
    public var kind: Kind
    /// 들은 말 그대로. 앱이 다듬지 않는다.
    public var text: String
    /// 증상 카탈로그의 항목과 이어 두면 나중에 실제 기록과 대조된다. 안 이어도 된다.
    public var symptomID: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        medicationID: UUID,
        kind: Kind = .heardFromDoctor,
        text: String,
        symptomID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.medicationID = medicationID
        self.kind = kind
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.symptomID = symptomID
        self.createdAt = createdAt
    }

    /// 빈 메모는 저장하지 않는다.
    public var isEmpty: Bool { text.isEmpty }
}

/// 들어 둔 메모를 실제 기록과 나란히 놓는다.
///
/// **세기만 한다.** "약 때문이다", "괜찮아졌다" 같은 말은 만들지 않는다.
/// 옆에 놓아 주면 판단은 진료실에서 사람이 한다(설계 01절).
public enum MedicationNoteDigest {

    public struct Observation: Hashable, Sendable, Identifiable {

        public let note: MedicationNote
        public let medicationName: String
        /// 이어 둔 증상의 이름. 안 이어 뒀으면 nil.
        public let symptomNameKo: String?
        /// 그 증상이 기간 안에 기록된 횟수. 증상을 안 이어 뒀으면 nil.
        public let recordedCount: Int?

        public var id: UUID { note.id }

        public init(
            note: MedicationNote,
            medicationName: String,
            symptomNameKo: String?,
            recordedCount: Int?
        ) {
            self.note = note
            self.medicationName = medicationName
            self.symptomNameKo = symptomNameKo
            self.recordedCount = recordedCount
        }
    }

    /// 메모마다 대조 결과를 붙인다.
    ///
    /// 증상 횟수는 **그 증상이 기록된 전체 횟수**다. 그 약이 원인이라고 말하는 것이 아니라,
    /// 들은 이야기 옆에 실제로 적힌 횟수를 놓아 주는 것뿐이다.
    public static func observations(
        notes: [MedicationNote],
        medications: [Medication],
        symptomEntries: [SymptomEntry],
        from start: Date,
        to end: Date,
        catalog: SymptomCatalog = Catalogs.symptoms
    ) -> [Observation] {

        var nameByID: [UUID: String] = [:]
        for medication in medications { nameByID[medication.id] = medication.name }

        // 기간 안의 증상만 미리 세어 둔다.
        var countBySymptom: [String: Int] = [:]
        for entry in symptomEntries where entry.startedAt >= start && entry.startedAt <= end {
            countBySymptom[entry.symptomID, default: 0] += 1
        }

        return notes.compactMap { note -> Observation? in
            // 주인 없는 메모는 내보내지 않는다. 약을 지웠는데 메모만 남은 경우다.
            guard let medicationName = nameByID[note.medicationID], !note.isEmpty else { return nil }

            let symptomName = note.symptomID.flatMap { catalog.symptom(id: $0)?.nameKo }
            let count = note.symptomID.map { countBySymptom[$0] ?? 0 }

            return Observation(
                note: note,
                medicationName: medicationName,
                symptomNameKo: symptomName,
                recordedCount: count
            )
        }
        .sorted { lhs, rhs in
            if lhs.medicationName != rhs.medicationName { return lhs.medicationName < rhs.medicationName }
            if lhs.note.kind != rhs.note.kind { return lhs.note.kind == .heardFromDoctor }
            return lhs.note.createdAt < rhs.note.createdAt
        }
    }

    /// 리포트에 그대로 앉히는 한 줄.
    ///
    /// "졸림 — 이 기간에 6번 기록" · "졸림 — 기록 없음" · 증상을 안 이어 뒀으면 메모 그대로.
    public static func lineKo(for observation: Observation) -> String {
        guard let symptomName = observation.symptomNameKo,
              let count = observation.recordedCount
        else {
            return observation.note.text
        }

        let tally = count == 0 ? "기록 없음" : "이 기간에 \(count)번 기록"
        return "\(symptomName) — \(tally)"
    }
}
