import XCTest
@testable import JanjanCore

/// 위젯이 "어느 시간대를 보여 줄지" 고르는 규칙.
///
/// 고르는 코드 자체(`TodayPlanReader`)는 SwiftData 를 써서 여기서 돌릴 수 없다.
/// 대신 그 코드가 기대는 성질을 잠근다 — 계획이 **시각 순으로 정렬돼 있고**,
/// 답한 줄과 안 답한 줄이 `isCompleted` 로 갈린다는 것. 위젯은 그 위에서
/// `first { !isCompleted }` 만 한다.
final class WidgetSelectionTests: XCTestCase {

    private let monday = Fixed.date(2026, 8, 17, 9, 0)

    private let medications = [
        Medication(id: Fixed.medA, name: "에스시탈로프람", strengthText: "10mg"),
        Medication(id: Fixed.medB, name: "쿠에티아핀", strengthText: "25mg")
    ]

    private let schedules = [
        Schedule(medicationID: Fixed.medA, slot: .morning, dosePerIntake: 1),
        Schedule(medicationID: Fixed.medB, slot: .bedtime, dosePerIntake: 1)
    ]

    private func plan(doses: [DoseEvent] = []) -> [DayPlan.SlotLine] {
        DayPlan.slots(
            on: monday,
            schedules: schedules,
            medications: medications,
            doseEvents: doses,
            calendar: Fixed.calendar
        )
    }

    /// 위젯이 고르는 방법. 앱 쪽 `TodayPlanReader.nextPending` 과 같은 한 줄이다.
    private func widgetPick(_ lines: [DayPlan.SlotLine]) -> DayPlan.SlotLine? {
        lines.first { !$0.isCompleted }
    }

    /// 그 시간대에 답을 하나 적는다.
    ///
    /// **`slotKey` 가 반드시 붙는다.** `DayPlan.slots` 는 `slotKey` 가 없는 사건을
    /// 조용히 버리므로, 빠뜨리면 "적었는데 안 적힌" 상태가 되고 테스트는 아무것도
    /// 확인하지 못한 채 통과한다. 그래서 사건을 손으로 만들지 않고 여기를 지난다.
    private func answer(
        _ slot: DoseSlot,
        for medicationID: UUID,
        _ status: DoseEvent.Status,
        source: DoseEvent.Source = .phone
    ) -> DoseEvent {
        let time = slot.defaultTime
        return DoseEvent(
            medicationID: medicationID,
            scheduledAt: Fixed.date(2026, 8, 17, time.hour, time.minute),
            status: status,
            source: source,
            slotKey: slot.storageKey
        )
    }

    // MARK: - 고르기

    func testPicksTheEarliestUnansweredSlot() {
        let picked = widgetPick(plan())
        XCTAssertEqual(picked?.slot, .morning, "아무것도 안 적었으면 가장 이른 시간대를 보여 줍니다")
    }

    /// **놓친 아침을 건너뛰지 않는다.**
    ///
    /// 저녁이 됐다고 아침을 지나쳐 버리면, 안 적은 아침이 조용히 묻힌다.
    /// 놓친 것을 계속 보여 주되 재촉하는 말은 붙이지 않는 것이 이 앱의 방식이다.
    func testDoesNotSkipAMissedEarlierSlot() {
        let bedtimeTaken = answer(.bedtime, for: Fixed.medB, .taken, source: .widget)
        let lines = plan(doses: [bedtimeTaken])

        // 취침이 실제로 적혔는지 먼저 본다. 이게 없으면 아래 단언이
        // '아무것도 안 적힌 계획' 을 보고도 통과해 버린다.
        XCTAssertEqual(lines.first(where: { $0.slot == .bedtime })?.isCompleted, true)

        XCTAssertEqual(widgetPick(lines)?.slot, .morning, "취침을 먼저 적었어도 안 적은 아침이 먼저입니다")
    }

    func testMovesOnOnceTheEarlierSlotIsAnswered() {
        let morningTaken = answer(.morning, for: Fixed.medA, .taken, source: .widget)

        let picked = widgetPick(plan(doses: [morningTaken]))
        XCTAssertEqual(picked?.slot, .bedtime)
    }

    /// 건너뜀도 '답한 것' 이다. 다시 물어보면 이미 내린 결정을 되묻는 셈이 된다.
    func testSkippedCountsAsAnswered() {
        let morningSkipped = answer(.morning, for: Fixed.medA, .skipped)

        let picked = widgetPick(plan(doses: [morningSkipped]))
        XCTAssertEqual(picked?.slot, .bedtime)
    }

    func testNothingLeftWhenEverySlotIsAnswered() {
        let doses = [
            answer(.morning, for: Fixed.medA, .taken, source: .widget),
            answer(.bedtime, for: Fixed.medB, .skipped)
        ]

        XCTAssertNil(widgetPick(plan(doses: doses)))
    }

    /// `slotKey` 가 없는 사건은 계획에 닿지 않는다.
    ///
    /// 오류도 경고도 없이 그냥 무시된다. 이걸 모르고 테스트에서 `slotKey` 를
    /// 빠뜨렸다가, 아무것도 적히지 않은 계획을 보고도 통과하는 테스트를 썼다.
    /// 다음 사람이 같은 데서 넘어지지 않게 동작을 적어 둔다.
    func testAnEventWithoutASlotKeyIsNotMatched() {
        let noSlotKey = DoseEvent(
            medicationID: Fixed.medA,
            scheduledAt: Fixed.date(2026, 8, 17, 8, 0),
            status: .taken,
            source: .widget
        )

        let morning = plan(doses: [noSlotKey]).first { $0.slot == .morning }
        XCTAssertEqual(morning?.isCompleted, false, "시간대를 모르는 기록은 어느 줄에도 붙지 않습니다")
    }

    // MARK: - 출처

    /// 저장된 문자열이라 값이 바뀌면 지난 기록이 다른 뜻이 된다.
    func testWidgetSourceRawValueIsStable() {
        XCTAssertEqual(DoseEvent.Source.widget.rawValue, "widget")
    }

    func testEverySourceHasItsOwnKoreanLabel() {
        let labels = DoseEvent.Source.allCases.map(\.labelKo)
        XCTAssertEqual(Set(labels).count, labels.count, "출처마다 다른 이름이어야 어디서 적었는지 구별됩니다")
        XCTAssertFalse(labels.contains(where: \.isEmpty))
    }
}
