import Foundation

/// 하루치 복용 계획 (설계 03절 · 10절).
///
/// 스케줄과 복용 사건에서 "오늘 이 시간대에 무엇이 남았는가" 를 만든다.
/// 오늘 화면·워치 스냅샷·알림 재예약이 전부 이 한 곳을 거친다. 그래야 폰과 워치가
/// 서로 다른 숫자를 말하지 않는다.
///
/// 재고와 같은 원칙을 쓴다 — **계획은 저장하지 않는다.** 매번 사건에서 다시 만든다.
/// 사용자가 어제 기록을 고쳐도 오늘의 화면이 어긋나지 않는다.
public enum DayPlan {

    // MARK: - 한 줄

    /// 시간대 한 줄 안의 약 하나.
    public struct Entry: Identifiable, Hashable, Sendable {

        /// 스케줄 ID. 한 약이 같은 시간대에 두 줄로 오지는 않으므로 이것으로 식별한다.
        public let id: UUID
        public let medicationID: UUID
        public let medicationName: String
        /// 1회 복용 개수. 반 알이면 0.5.
        public let dose: Decimal
        /// 기록된 상태. 아직 아무 기록도 없으면 nil.
        public let status: DoseEvent.Status?
        /// 대응하는 저장된 사건. 답을 고쳐 쓸 때 이 ID 로 찾는다.
        public let eventID: UUID?

        public init(
            id: UUID,
            medicationID: UUID,
            medicationName: String,
            dose: Decimal,
            status: DoseEvent.Status? = nil,
            eventID: UUID? = nil
        ) {
            self.id = id
            self.medicationID = medicationID
            self.medicationName = medicationName
            self.dose = DecimalQuantity.snapToQuarter(dose)
            self.status = status
            self.eventID = eventID
        }

        /// 사용자가 답을 준 줄인가.
        /// 미기록은 답이 아니다 — 알림에 응답하지 않은 것과 건너뛰기로 정한 것은 다르다.
        public var isAnswered: Bool {
            guard let status else { return false }
            return status != .unrecorded
        }
    }

    /// 한 시간대(아침·점심·저녁·취침·사용자 정의) 한 줄.
    public struct SlotLine: Identifiable, Hashable, Sendable {

        public let slot: DoseSlot
        /// 이 시간대에 실제로 알림이 가는 시각. 같은 시간대에 여러 시각이 섞이면 가장 이른 것.
        public let time: TimeOfDay
        public let entries: [Entry]

        public var id: String { slot.storageKey }
        public var slotKey: String { slot.storageKey }

        public init(slot: DoseSlot, time: TimeOfDay, entries: [Entry]) {
            self.slot = slot
            self.time = time
            self.entries = entries
        }

        /// 이 시간대의 약을 전부 답했는가. 빈 줄은 완료로 보지 않는다.
        public var isCompleted: Bool {
            !entries.isEmpty && entries.allSatisfy(\.isAnswered)
        }

        /// 아직 답하지 않은 약의 수.
        public var pendingCount: Int {
            entries.filter { !$0.isAnswered }.count
        }

        public var medicationNames: [String] {
            entries.map(\.medicationName)
        }

        /// 하루 안에서의 정렬 기준. 사용자가 시각을 옮겼으면 옮긴 시각을 따른다.
        public var sortKey: Int { time.minutesFromMidnight }
    }

    // MARK: - 계획 세우기

    /// `day` 하루의 시간대별 계획.
    ///
    /// - Parameters:
    ///   - day: 계획을 만들 날짜. 시·분은 무시하고 그 날 전체를 본다.
    ///   - schedules: 전체 스케줄. 그 날 살아 있지 않은 줄은 내부에서 걸러 낸다.
    ///   - medications: 이름을 붙이는 데 쓴다. 중단한 약과 목록에 없는 약은 빠진다.
    ///   - doseEvents: 전체 복용 사건. 그 날의 정기 예정분만 짝지어 본다.
    public static func slots(
        on day: Date,
        schedules: [Schedule],
        medications: [Medication],
        doseEvents: [DoseEvent],
        calendar: Calendar = .current
    ) -> [SlotLine] {

        // 이름을 붙일 수 있고 아직 복용 중인 약만 계획에 올린다.
        var activeMedications: [UUID: Medication] = [:]
        for medication in medications where medication.status == .active {
            activeMedications[medication.id] = medication
        }

        let todaysSchedules = schedules.filter { schedule in
            activeMedications[schedule.medicationID] != nil
                && schedule.isActive(on: day, calendar: calendar)
        }

        // 그 날의 정기 예정분 사건만 미리 추려 둔다. 스케줄마다 전체를 훑지 않기 위해서다.
        var eventsByKey: [String: [DoseEvent]] = [:]
        for event in doseEvents {
            guard event.kind == .scheduled, let slotKey = event.slotKey else { continue }
            guard calendar.isDate(event.effectiveDate, inSameDayAs: day) else { continue }
            eventsByKey["\(event.medicationID.uuidString)|\(slotKey)", default: []].append(event)
        }

        let grouped = Dictionary(grouping: todaysSchedules, by: { $0.slot.storageKey })

        return grouped.compactMap { key, group -> SlotLine? in
            guard let slot = DoseSlot(storageKey: key) else { return nil }

            let sorted = group.sorted { lhs, rhs in
                if lhs.timeOfDay != rhs.timeOfDay { return lhs.timeOfDay < rhs.timeOfDay }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            guard let earliest = sorted.first else { return nil }

            let entries = sorted.compactMap { schedule -> Entry? in
                guard let medication = activeMedications[schedule.medicationID] else { return nil }
                let event = latestEvent(
                    in: eventsByKey["\(schedule.medicationID.uuidString)|\(key)"] ?? []
                )
                return Entry(
                    id: schedule.id,
                    medicationID: schedule.medicationID,
                    medicationName: medication.name,
                    dose: schedule.dosePerIntake,
                    status: event?.status,
                    eventID: event?.id
                )
            }

            guard !entries.isEmpty else { return nil }
            return SlotLine(slot: slot, time: earliest.timeOfDay, entries: entries)
        }
        .sorted { lhs, rhs in
            if lhs.sortKey != rhs.sortKey { return lhs.sortKey < rhs.sortKey }
            return lhs.slotKey < rhs.slotKey
        }
    }

    /// 같은 약·같은 시간대에 사건이 여러 개면 가장 나중 것을 진실로 본다.
    /// (알림으로 건너뜀을 눌렀다가 앱에서 복용함으로 고친 경우가 여기 걸린다.)
    private static func latestEvent(in events: [DoseEvent]) -> DoseEvent? {
        events.max { lhs, rhs in
            if lhs.effectiveDate != rhs.effectiveDate { return lhs.effectiveDate < rhs.effectiveDate }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // MARK: - 요약

    /// 오늘 아직 답하지 않은 약의 총 개수.
    public static func pendingCount(in slots: [SlotLine]) -> Int {
        slots.reduce(0) { $0 + $1.pendingCount }
    }

    /// 아직 답하지 않은 시간대의 수. 오늘 화면 인사말이 쓴다.
    public static func pendingSlotCount(in slots: [SlotLine]) -> Int {
        slots.filter { !$0.isCompleted }.count
    }

    /// 지금 시각 기준으로 가장 먼저 답해야 할 시간대.
    /// 남은 것이 없으면 nil — 화면은 "다 챙기셨어요" 를 보인다.
    public static func nextPendingSlot(
        in slots: [SlotLine],
        at now: Date,
        calendar: Calendar = .current
    ) -> SlotLine? {
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let pending = slots.filter { !$0.isCompleted }
        // 아직 오지 않은 시간대가 있으면 그 중 가장 이른 것, 다 지났으면 지난 것 중 가장 이른 것.
        return pending.first { $0.sortKey >= minutes } ?? pending.first
    }

    // MARK: - 워치 스냅샷

    /// 같은 계획을 워치가 그릴 수 있는 형태로 굽는다.
    /// 워치는 재고도 스케줄도 모르고 이 스냅샷만 그린다(설계 10절).
    public static func watchSnapshot(
        on day: Date,
        schedules: [Schedule],
        medications: [Medication],
        doseEvents: [DoseEvent],
        calendar: Calendar = .current,
        generatedAt: Date = Date()
    ) -> WatchSnapshot {

        let lines = slots(
            on: day,
            schedules: schedules,
            medications: medications,
            doseEvents: doseEvents,
            calendar: calendar
        )

        return WatchSnapshot(
            generatedAt: generatedAt,
            dateText: shortDateText(for: day),
            slots: lines.map { line in
                WatchSnapshot.SlotLine(
                    slotKey: line.slotKey,
                    labelKo: line.slot.labelKo,
                    timeText: line.time.description,
                    medicationNames: line.medicationNames,
                    isCompleted: line.isCompleted
                )
            },
            remainingCountToday: pendingCount(in: lines)
        )
    }

    /// "8/17". 워치 화면 맨 위 한 줄.
    static func shortDateText(for day: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: day)
    }
}
