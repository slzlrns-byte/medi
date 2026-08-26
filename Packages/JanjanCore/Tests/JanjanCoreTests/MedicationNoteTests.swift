import XCTest
@testable import JanjanCore

/// 약에 딸린 메모와, 그것을 실제 기록과 나란히 놓는 규칙.
///
/// 이 기능은 식약처 이상반응 원문을 싣지 않기로 한 자리에 들어왔다.
/// 그러니 여기서 앱이 판단하는 문장을 만들면 바꾼 의미가 없다.
final class MedicationNoteTests: XCTestCase {

    private let start = Fixed.date(2026, 8, 1, 0, 0)
    private let end = Fixed.date(2026, 8, 28, 23, 59)

    private var medications: [Medication] {
        [
            Medication(id: Fixed.medA, name: "에스시탈로프람"),
            Medication(id: Fixed.medB, name: "쿠에티아핀")
        ]
    }

    private func note(
        _ text: String,
        med: UUID? = nil,
        kind: MedicationNote.Kind = .heardFromDoctor,
        symptom: String? = nil,
        day: Int = 1
    ) -> MedicationNote {
        MedicationNote(
            medicationID: med ?? Fixed.medA,
            kind: kind,
            text: text,
            symptomID: symptom,
            createdAt: Fixed.date(2026, 8, day, 10, 0)
        )
    }

    private func symptom(_ id: String, day: Int) -> SymptomEntry {
        SymptomEntry(symptomID: id, severity: 5, startedAt: Fixed.date(2026, 8, day, 21, 0))
    }

    private func observe(
        _ notes: [MedicationNote],
        symptoms: [SymptomEntry] = []
    ) -> [MedicationNoteDigest.Observation] {
        MedicationNoteDigest.observations(
            notes: notes,
            medications: medications,
            symptomEntries: symptoms,
            from: start,
            to: end
        )
    }

    // MARK: - 담기

    func testTextIsKeptAsWritten() {
        // 사용자의 말을 다듬지 않는다. 앞뒤 공백만 턴다.
        let saved = note("  처음 며칠 졸릴 수 있다고 하심  ")
        XCTAssertEqual(saved.text, "처음 며칠 졸릴 수 있다고 하심")
    }

    func testEmptyNoteIsMarkedEmpty() {
        XCTAssertTrue(note("   ").isEmpty)
        XCTAssertFalse(note("졸림").isEmpty)
    }

    func testEmptyNotesAreDropped() {
        XCTAssertTrue(observe([note("  ")]).isEmpty)
    }

    func testOrphanNoteIsDropped() {
        // 약을 지웠는데 메모만 남은 경우. 이름을 붙일 수 없으면 내보내지 않는다.
        XCTAssertTrue(observe([note("졸림", med: UUID())]).isEmpty)
    }

    // MARK: - 대조

    func testLinkedSymptomIsCounted() {
        let notes = [note("처음 며칠 졸릴 수 있다고 하심", symptom: "anxiety_restless")]
        let symptoms = [
            symptom("anxiety_restless", day: 3),
            symptom("anxiety_restless", day: 9),
            symptom("anxiety_restless", day: 20)
        ]

        let result = observe(notes, symptoms: symptoms)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].recordedCount, 3)
        XCTAssertEqual(result[0].symptomNameKo, "불안·초조")
        XCTAssertEqual(result[0].medicationName, "에스시탈로프람")
    }

    func testLinkedSymptomWithNoRecordsCountsZero() {
        // 안 겪은 것도 사실이다. nil 이 아니라 0 이어야 "기록 없음" 을 말할 수 있다.
        let result = observe([note("졸림", symptom: "anxiety_restless")])
        XCTAssertEqual(result[0].recordedCount, 0)
    }

    func testUnlinkedNoteHasNoCount() {
        // 증상을 안 이어 뒀으면 셀 것이 없다. 0 이 아니라 nil 이다.
        let result = observe([note("술은 피하라고 하심")])
        XCTAssertNil(result[0].recordedCount)
        XCTAssertNil(result[0].symptomNameKo)
    }

    func testSymptomsOutsideThePeriodAreNotCounted() {
        let notes = [note("졸림", symptom: "anxiety_restless")]
        let symptoms = [
            symptom("anxiety_restless", day: 3),
            SymptomEntry(
                symptomID: "anxiety_restless",
                severity: 5,
                startedAt: Fixed.date(2026, 7, 20, 21, 0)
            )
        ]
        XCTAssertEqual(observe(notes, symptoms: symptoms)[0].recordedCount, 1)
    }

    func testOtherSymptomsAreNotCounted() {
        let notes = [note("졸림", symptom: "anxiety_restless")]
        XCTAssertEqual(observe(notes, symptoms: [symptom("dry_mouth", day: 5)])[0].recordedCount, 0)
    }

    // MARK: - 차례

    func testSortedByMedicationThenHeardBeforeQuestions() {
        let notes = [
            note("B 에게 여쭤볼 것", med: Fixed.medB, kind: .questionForDoctor, day: 2),
            note("A 에게 여쭤볼 것", med: Fixed.medA, kind: .questionForDoctor, day: 2),
            note("B 에게 들은 것", med: Fixed.medB, kind: .heardFromDoctor, day: 1),
            note("A 에게 들은 것", med: Fixed.medA, kind: .heardFromDoctor, day: 1)
        ]

        let result = observe(notes).map(\.note.text)
        XCTAssertEqual(
            result,
            ["A 에게 들은 것", "A 에게 여쭤볼 것", "B 에게 들은 것", "B 에게 여쭤볼 것"]
        )
    }

    // MARK: - 문장

    func testLineForLinkedSymptom() {
        let notes = [note("졸림", symptom: "anxiety_restless")]
        let symptoms = [symptom("anxiety_restless", day: 3), symptom("anxiety_restless", day: 4)]
        let line = MedicationNoteDigest.lineKo(for: observe(notes, symptoms: symptoms)[0])
        XCTAssertEqual(line, "불안·초조 — 이 기간에 2번 기록")
    }

    func testLineWhenNothingWasRecorded() {
        let line = MedicationNoteDigest.lineKo(for: observe([note("졸림", symptom: "anxiety_restless")])[0])
        XCTAssertEqual(line, "불안·초조 — 기록 없음")
    }

    func testLineForUnlinkedNoteIsTheNoteItself() {
        let line = MedicationNoteDigest.lineKo(for: observe([note("술은 피하라고 하심")])[0])
        XCTAssertEqual(line, "술은 피하라고 하심")
    }

    /// 이 기능을 넣은 이유가 "앱이 판단하지 않게" 였다. 그 선을 문장에서 지킨다.
    func testLinesNeverJudge() {
        let notes = [
            note("졸림", symptom: "anxiety_restless"),
            note("입마름", symptom: "dry_mouth", day: 2)
        ]
        let symptoms = (1...9).map { symptom("anxiety_restless", day: $0) }

        for observation in observe(notes, symptoms: symptoms) {
            let line = MedicationNoteDigest.lineKo(for: observation)
            XCTAssertFalse(line.contains("!"))
            for word in ["때문", "부작용이 맞", "심각", "위험", "좋아졌", "나빠졌", "괜찮"] {
                XCTAssertFalse(line.contains(word), "판단하는 말이 들어갔습니다: \(line)")
            }
        }
    }

    func testKindLabelsAreCalm() {
        for kind in MedicationNote.Kind.allCases {
            XCTAssertFalse(kind.titleKo.contains("!"))
            XCTAssertFalse(kind.placeholderKo.isEmpty)
        }
        XCTAssertEqual(MedicationNote.Kind.heardFromDoctor.titleKo, "선생님이 말씀하신 것")
    }
}
