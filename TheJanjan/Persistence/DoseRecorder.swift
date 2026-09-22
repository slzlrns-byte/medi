import Foundation
import SwiftData
import JanjanCore

/// 복용 기록을 저장하는 단 하나의 통로.
///
/// 오늘 화면·알림 액션·워치가 전부 여기를 지난다. 저장 규칙이 세 곳에 흩어지면
/// 같은 사실이 서로 다르게 적히고, 재고는 그 차이를 그대로 물려받는다.
///
/// **덮어쓰기가 이 파일의 핵심이다.** 같은 날 · 같은 시간대 · 같은 약의 기록은
/// 새 줄을 만들지 않고 있던 줄을 고친다. 새 줄을 만들면 알림에서 "복용함" 을 누른 뒤
/// 앱에서 "건너뜀" 으로 고쳤을 때, 재고 계산이 복용함 한 건을 계속 세어
/// 실제보다 한 알 적게 남았다고 말한다(설계 05절의 "복용함만 뺀다" 가 깨진다).
@MainActor
enum DoseRecorder {

    /// 오늘 시간대에 답이 남을 때 앱이 되물음 알림을 걷도록 끼우는 고리.
    ///
    /// NotificationManager 를 여기서 직접 부르면 안 된다 - 이 파일은 위젯
    /// 타깃도 컴파일하는데(project.yml 의 경고 참조) 거기에는 그 클래스가
    /// 없다. 앱만 AppServices 가 이 고리를 채우고, 위젯에서는 비어 있다 -
    /// 위젯에서 남긴 기록의 되물음은 앱이 다음에 앞으로 나올 때 정리된다.
    static var onScheduledRecordToday: ((_ slotKey: String) -> Void)?

    /// 한 약의 한 시간대 기록을 남기거나 고친다.
    ///
    /// - Parameters:
    ///   - day: 어느 날의 예정분인가. 화면은 보고 있는 날짜를 그대로 넘긴다.
    ///     nil 이면 `moment` 근처에서 알아서 고른다(알림·워치처럼 날짜를 모르는 경로).
    ///   - moment: 실제로 누른 시각. 복용함일 때만 `actualAt` 으로 남는다.
    ///   - quantity: 개수. nil 이면 그 시간대 스케줄에서 가져오고, 그것도 없으면 1정.
    @discardableResult
    static func record(
        medicationID: UUID,
        slotKey: String,
        status: DoseEvent.Status,
        source: DoseEvent.Source,
        on day: Date? = nil,
        at moment: Date = Date(),
        quantity: Decimal? = nil,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> DoseEventRecord {

        let schedule = scheduleRecord(medicationID: medicationID, slotKey: slotKey, in: context)
        // 새로 넣는 쪽은 DoseEvent 의 초기화 함수가 스냅해 주지만 고쳐 쓰는 쪽은 그냥 들어간다.
        // 여기서 한 번 맞춰 두면 두 갈래가 같은 값을 남긴다.
        let amount = DecimalQuantity.snapToQuarter(quantity ?? schedule?.dosePerIntake ?? 1)
        let time = plannedTime(for: schedule, slotKey: slotKey)
        let targetDay = day ?? plannedDay(near: moment, scheduleTime: time, calendar: calendar)
        let scheduledAt = time.date(on: targetDay, calendar: calendar)

        // 오늘 시간대에 답이 남으면 걸려 있던 되물음(Pro 재알림)은 걷는다 -
        // 이미 먹었다고 적었는데 "아직 기록이 없어요" 가 또 오면 안 된다.
        if calendar.isDate(targetDay, inSameDayAs: moment) {
            onScheduledRecordToday?(slotKey)
        }

        // 고쳐 쓸 때도 그 칸의 줄을 **전부** 본다. 한 줄만 고치면, 두 기기가
        // 각자 남긴 날에 사용자의 정정이 안 고쳐진 옛 줄에 밀린다 - "건너뜀"
        // 으로 고쳤는데 남아 있던 "복용함" 이 더 나중 시각이라 이겼다
        // (QA 2026-09-21). 하나만 살리고 나머지는 걷는다.
        let existingRecords = allRecords(
            medicationID: medicationID,
            slotKey: slotKey,
            on: targetDay,
            in: context,
            calendar: calendar
        )
        // **이미 지나간 시간대는 그 시각으로 박는다.** 예정이 08:00 인 약을 21:00
        // 에 "복용함" 으로 적으면 `actualAt` 은 08:00 이다. 재고는 `actualAt`
        // 순으로 세고 "다시 세기" 의 정정은 그 앞을 전부 버리는 기준점이라,
        // 누른 시각을 그대로 쓰면 **세고 나서 적으면 한 알이 더 빠지고 적고
        // 나서 세면 안 빠졌다**. 예전에는 오늘 화면만 이 규칙을 알고 알림·
        // 위젯·워치·시리는 누른 시각을 넘겨 같은 하루가 길에 따라 달랐다
        // (QA 2026-09-22). 규칙을 호출부가 아니라 여기 한 곳에 둔다.
        // 아직 오지 않은 시간대를 미리 누르면 지금 시각이 더 이르므로 그대로다.
        let takenAt = min(scheduledAt, moment)

        if let existing = existingRecords.first {
            for extra in existingRecords.dropFirst() { context.delete(extra) }
            existing.statusRaw = status.rawValue
            existing.actualAt = (status == .taken) ? takenAt : nil
            existing.sourceRaw = source.rawValue
            existing.quantity = amount
            existing.scheduledAt = scheduledAt
            // 상태가 복용함·미기록으로 바뀌면 예전 건너뜀 사유는 더 이상 사실이 아니다.
            if status != .skipped { existing.skipReason = nil }
            return existing
        }

        let event = DoseEvent(
            medicationID: medicationID,
            scheduledAt: scheduledAt,
            actualAt: (status == .taken) ? takenAt : nil,
            status: status,
            source: source,
            quantity: amount,
            kind: .scheduled,
            slotKey: slotKey
        )
        let record = DoseEventRecord.make(from: event)
        context.insert(record)
        return record
    }

    /// 그 칸에 **사용자가 준 답**이 이미 있는가. 앱이 채운 미기록(`.automatic`)
    /// 은 답이 아니다. 알림·워치의 "전부 복용함" 이 앱 타일과 같은 규칙으로
    /// 미답만 채우기 위해 묻는다.
    static func isAnswered(
        medicationID: UUID,
        slotKey: String,
        near moment: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> Bool {
        let schedule = scheduleRecord(medicationID: medicationID, slotKey: slotKey, in: context)
        let time = plannedTime(for: schedule, slotKey: slotKey)
        let day = plannedDay(near: moment, scheduleTime: time, calendar: calendar)
        return allRecords(medicationID: medicationID, slotKey: slotKey, on: day, in: context, calendar: calendar)
            .contains { record in
                guard let status = DoseEvent.Status(rawValue: record.statusRaw) else { return false }
                if status == .unrecorded, record.sourceRaw == DoseEvent.Source.automatic.rawValue { return false }
                return true
            }
    }

    /// 필요시(PRN) 복용. 시간대가 없으므로 항상 새 줄로 쌓인다 —
    /// 하루에 두 번 먹었으면 두 번 먹은 것이 사실이다.
    @discardableResult
    static func recordAsNeeded(
        medicationID: UUID,
        quantity: Decimal,
        source: DoseEvent.Source,
        at moment: Date = Date(),
        in context: ModelContext
    ) -> DoseEventRecord {
        let event = DoseEvent(
            medicationID: medicationID,
            scheduledAt: moment,
            actualAt: moment,
            status: .taken,
            source: source,
            quantity: quantity,
            kind: .asNeeded,
            slotKey: nil
        )
        let record = DoseEventRecord.make(from: event)
        context.insert(record)
        return record
    }

    // MARK: - 찾기

    /// 그 시간대 기록을 지워 **아직 답하지 않은 상태로 되돌린다.**
    ///
    /// 미기록으로 바꾸지 않는 이유: 미기록은 "지나갔는데 답이 없다" 는 뜻이라
    /// 리포트의 분모에 들어간다. 잘못 누른 것을 되돌리는 것은 그것과 다르다 -
    /// 아무 일도 없던 것으로 만들어야 다시 물어볼 수 있다(사용자 요청 2026-09-21).
    ///
    /// - Returns: 지운 것이 있으면 참.
    @discardableResult
    static func clear(
        medicationID: UUID,
        slotKey: String,
        on day: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> Bool {
        // **맞는 줄을 전부 지운다.** 하나만 지우면, 두 기기가 동기화 전에
        // 각자 기록해 줄이 둘인 날에 되돌리기가 조용히 실패했다 - 남은 줄이
        // 여전히 "복용함" 이라 화면은 그대로 완료였고 재고도 안 돌아왔다
        // (QA 2026-09-21). 읽는 쪽(collapsedDoses)은 이미 중복을 하나로 묶고
        // 있었는데 쓰는 쪽만 한 줄을 봤다.
        let records = allRecords(
            medicationID: medicationID,
            slotKey: slotKey,
            on: day,
            in: context,
            calendar: calendar
        )
        guard !records.isEmpty else { return false }
        for record in records { context.delete(record) }
        return true
    }

    /// 그 날 · 그 시간대 · 그 약의 기록. 여럿이면 가장 나중 것.
    static func existingRecord(
        medicationID: UUID,
        slotKey: String,
        on day: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> DoseEventRecord? {

        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }

        // #Predicate 안에서는 옵셔널끼리만 비교할 수 있다. slotKey 가 String? 이라 맞춰 준다.
        let key: String? = slotKey
        let scheduledKind = DoseEvent.Kind.scheduled.rawValue

        var descriptor = FetchDescriptor<DoseEventRecord>(
            predicate: #Predicate { record in
                record.medicationID == medicationID
                    && record.slotKey == key
                    && record.kindRaw == scheduledKind
                    && record.scheduledAt >= start
                    && record.scheduledAt < end
            },
            sortBy: [SortDescriptor(\.scheduledAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// 그 날 · 그 시간대 · 그 약의 기록 **전부**. 기기 간 동기화로 줄이
    /// 둘 이상일 수 있어서, 지우거나 고쳐 쓸 때는 이쪽을 쓴다.
    static func allRecords(
        medicationID: UUID,
        slotKey: String,
        on day: Date,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> [DoseEventRecord] {

        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let key: String? = slotKey
        let scheduledKind = DoseEvent.Kind.scheduled.rawValue

        let descriptor = FetchDescriptor<DoseEventRecord>(
            predicate: #Predicate { record in
                record.medicationID == medicationID
                    && record.slotKey == key
                    && record.kindRaw == scheduledKind
                    && record.scheduledAt >= start
                    && record.scheduledAt < end
            },
            sortBy: [SortDescriptor(\.scheduledAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func scheduleRecord(
        medicationID: UUID,
        slotKey: String,
        in context: ModelContext
    ) -> ScheduleRecord? {
        // 정렬 없이 하나만 집으면, 같은 시간대에 스케줄이 둘 생겼을 때(두 기기가 동기화
        // 전에 각자 만든 경우) 아무거나 골라 엉뚱한 개수와 시각을 기록한다.
        var descriptor = FetchDescriptor<ScheduleRecord>(
            predicate: #Predicate { record in
                record.medicationID == medicationID && record.slotKey == slotKey
            },
            sortBy: [SortDescriptor(\.hour), SortDescriptor(\.minute), SortDescriptor(\.id)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// 알림에 답한 시각이 **어느 날의 예정분**인지 고른다.
    ///
    /// 규칙은 하나다: 아직 오지도 않은 예정분에는 답을 붙이지 않는다.
    /// 이미 지난 것 중 가장 나중 것을 고르고, 조금 이르게 누른 경우만 봐 준다.
    ///
    /// 예전에는 어제·오늘·내일 중 "지금과 가장 가까운" 것을 골랐는데, 그러면
    /// 하루 한 번 먹는 약에서 **12시간이 경계**가 되어 버린다. 아침 8시 약을
    /// 그날 밤 9시에 뒤늦게 기록하면 내일 아침 8시가 더 가까워서 내일 줄에 적히고,
    /// 다음 날 진짜로 아침 약을 먹고 기록하면 그 줄을 덮어쓴다.
    /// 두 번 먹은 것이 한 번으로 남고, 재고는 한 알만 줄고, 오늘 아침은 영영 미기록이 된다.
    static func plannedDay(
        near moment: Date,
        scheduleTime: TimeOfDay,
        calendar: Calendar = .current
    ) -> Date {

        // 알림이 울리기 직전에 미리 먹고 누르는 사람이 있다. 그 정도는 그 날 것으로 본다.
        let earlyGrace: TimeInterval = 2 * 60 * 60
        let cutoff = moment.addingTimeInterval(earlyGrace)

        let today = calendar.startOfDay(for: moment)
        var best: Date?
        var bestOccurrence: Date?

        for offset in -1...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let occurrence = scheduleTime.date(on: day, calendar: calendar)
            guard occurrence <= cutoff else { continue }
            if let current = bestOccurrence, occurrence <= current { continue }
            bestOccurrence = occurrence
            best = day
        }

        // 그 시간대가 오늘도 어제도 아직 오지 않았다면(시각을 방금 옮긴 경우 등)
        // 가장 가까운 지난 날인 어제로 둔다.
        return best ?? calendar.date(byAdding: .day, value: -1, to: today) ?? today
    }

    /// 사용자가 시각을 옮겼으면 옮긴 시각, 아니면 그 시간대의 기본 시각.
    static func plannedTime(for schedule: ScheduleRecord?, slotKey: String) -> TimeOfDay {
        if let schedule {
            return TimeOfDay(hour: schedule.hour, minute: schedule.minute)
        }
        return DoseSlot(storageKey: slotKey)?.defaultTime ?? TimeOfDay(hour: 9, minute: 0)
    }
}
