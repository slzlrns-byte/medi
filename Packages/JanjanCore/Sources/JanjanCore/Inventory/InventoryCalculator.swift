import Foundation

/// 재고 · 복약률 · 소진 예측 계산기 (설계 05절).
///
/// 원칙 하나: **재고는 저장하지 않는다.** 잔여 개수는 사건의 합으로 매번 다시 계산한다.
/// 그래야 사용자가 지난주 기록을 고쳐도 오늘의 잔여가 어긋나지 않는다.
///
/// 계산 규칙
/// 1. 마지막 `직접 정정(correction)` 이 기준점이다. 그 이전 사건은 전부 무시한다.
/// 2. 기준점 이후의 `보충(refill)` 을 더한다.
/// 3. 기준점 이후의 `복용함(taken)` DoseEvent 개수를 뺀다.
/// 4. `건너뜀`·`미기록` 은 차감하지 않는다 — 실제로 약이 줄지 않았으므로.
///    대신 재고가 실제보다 많아 보일 수 있으니 소진 예측에 복약률을 곱해 보정한다.
public enum InventoryCalculator {

    // MARK: - 잔여 개수

    /// 약 하나의 `asOf` 시점 잔여 개수.
    ///
    /// - Parameters:
    ///   - medicationID: 계산할 약.
    ///   - stockEvents: 이 약의(또는 전체) 보충·정정 사건. 내부에서 약 ID 로 걸러 낸다.
    ///   - doseEvents: 이 약의(또는 전체) 복용 사건.
    ///   - asOf: 이 시각까지의 사건만 반영한다. 미래에 예정된 사건은 세지 않는다.
    public static func remaining(
        for medicationID: UUID,
        stockEvents: [StockEvent],
        doseEvents: [DoseEvent],
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> Decimal {

        // 같은 시각에 여러 사건이 있을 때의 순서.
        // 정정(0) → 보충(1) → 복용(2). 정정이 먼저 기준을 세우고 그 위에 나머지가 얹힌다.
        enum Step {
            case correction(Decimal)
            case refill(Decimal)
            case consumption(Decimal)

            var rank: Int {
                switch self {
                case .correction: return 0
                case .refill: return 1
                case .consumption: return 2
                }
            }
        }

        var steps: [(date: Date, step: Step)] = []

        for event in stockEvents where event.medicationID == medicationID {
            guard event.occurredAt <= asOf else { continue }
            switch event.kind {
            case .correction(let setTo):
                steps.append((date: event.occurredAt, step: .correction(setTo)))
            case .refill(let quantity):
                steps.append((date: event.occurredAt, step: .refill(quantity)))
            }
        }

        for event in collapsedDoses(for: medicationID, in: doseEvents, calendar: calendar) {
            guard event.status.consumesStock else { continue }
            let when = event.effectiveDate
            guard when <= asOf else { continue }
            steps.append((date: when, step: .consumption(event.quantity)))
        }

        steps.sort { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.step.rank < rhs.step.rank
        }

        var running: Decimal = 0
        for entry in steps {
            switch entry.step {
            case .correction(let setTo): running = setTo
            case .refill(let quantity): running += quantity
            case .consumption(let quantity): running -= quantity
            }
        }

        return DecimalQuantity.round(running, scale: 4)
    }

    /// 같은 날 · 같은 시간대 · 같은 약의 **정기** 복용 사건이 둘 이상이면 가장 나중 것만 남긴다.
    ///
    /// 기기가 둘이면 이런 일이 생긴다. 워치에서 "복용함" 을 누르고, 동기화가 오기 전에
    /// 폰에서 한 번 더 누른다. 두 기기가 각자 새 줄을 만들고 CloudKit 은 둘 다 남긴다 —
    /// SwiftData + CloudKit 에서는 유니크 제약을 걸 수 없어서(Records.swift 머리말) 막을 수가 없다.
    ///
    /// 화면은 이미 이 경우를 견딘다. `DayPlan` 이 가장 나중 것만 골라 한 줄로 그린다.
    /// 그런데 재고만 둘 다 빼면, 사용자는 "완료" 한 줄을 보면서 두 알이 사라진 것을 보게 되고
    /// 왜 어긋났는지 알 길이 없다. 그래서 두 계산이 같은 규칙을 쓰게 맞춘다.
    ///
    /// **필요시(PRN) 약은 묶지 않는다.** 시간대가 없고, 하루에 두 번 먹었으면
    /// 두 번 먹은 것이 사실이다.
    static func collapsedDoses(
        for medicationID: UUID,
        in doseEvents: [DoseEvent],
        calendar: Calendar = .current
    ) -> [DoseEvent] {

        var latestBySlot: [String: DoseEvent] = [:]
        var untouched: [DoseEvent] = []

        for event in doseEvents where event.medicationID == medicationID {
            guard event.kind == .scheduled, let slotKey = event.slotKey else {
                untouched.append(event)
                continue
            }

            let day = calendar.startOfDay(for: event.scheduledAt)
            let key = "\(slotKey)|\(day.timeIntervalSinceReferenceDate)"

            if let kept = latestBySlot[key], isLater(kept, than: event) { continue }
            latestBySlot[key] = event
        }

        return untouched + Array(latestBySlot.values)
    }

    /// `DayPlan.latestEvent` 와 같은 순서 규칙. 둘이 어긋나면 화면과 재고가 다시 갈라진다.
    private static func isLater(_ lhs: DoseEvent, than rhs: DoseEvent) -> Bool {
        if lhs.effectiveDate != rhs.effectiveDate { return lhs.effectiveDate > rhs.effectiveDate }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    // MARK: - 복약률

    /// 기간 안의 복약률 = 복용함 ÷ (복용함 + 건너뜀 + 미기록).
    ///
    /// 정기 예정분(`kind == .scheduled`)만 센다. 필요시 약은 안 먹는 게 정상이라
    /// 분모에 넣으면 복약률이 근거 없이 내려간다.
    ///
    /// - Returns: 0…1 사이 비율. 셀 사건이 하나도 없으면 nil.
    public static func adherenceRate(
        doseEvents: [DoseEvent],
        medicationID: UUID? = nil,
        from start: Date,
        to end: Date
    ) -> Decimal? {

        var taken = 0
        var total = 0

        for event in doseEvents {
            if let medicationID, event.medicationID != medicationID { continue }
            guard event.kind == .scheduled else { continue }
            let when = event.effectiveDate
            guard when >= start, when <= end else { continue }
            total += 1
            if event.status == .taken { taken += 1 }
        }

        guard total > 0 else { return nil }
        return Decimal(taken) / Decimal(total)
    }

    /// 최근 4주(28일) 복약률. 소진 예측이 쓰는 기본값이다.
    public static func adherenceRate(
        doseEvents: [DoseEvent],
        medicationID: UUID? = nil,
        last28DaysEndingAt end: Date,
        calendar: Calendar = .current
    ) -> Decimal? {
        let start = calendar.date(byAdding: .day, value: -28, to: end) ?? end
        return adherenceRate(doseEvents: doseEvents, medicationID: medicationID, from: start, to: end)
    }

    // MARK: - 소진 예측

    /// 복약률이 0 이어도 예측이 무한대로 튀지 않게 두는 하한.
    /// 실제로 한 알도 안 먹은 사람에게 "9999일 남음" 이라고 말할 수는 없다.
    public static let minimumAdherence = Decimal(string: "0.05") ?? 0

    /// 며칠 뒤에 약이 떨어지는지.
    ///
    /// `잔여 ÷ (하루 예정 개수 × 복약률)`.
    /// 복약률 70% 면 실제로는 하루 0.7개씩 줄어드니 예측이 뒤로 밀린다.
    ///
    /// - Returns: 남은 날 수(소수). 하루 예정 개수가 0 이하이면 nil(예측 불가).
    public static func projectedDaysRemaining(
        remaining: Decimal,
        dailyScheduledQuantity: Decimal,
        adherence: Decimal?
    ) -> Decimal? {

        guard dailyScheduledQuantity > 0 else { return nil }
        if remaining <= 0 { return 0 }

        let rate = max(adherence ?? 1, minimumAdherence)
        let dailyBurn = dailyScheduledQuantity * rate
        guard dailyBurn > 0 else { return nil }

        // 나눗셈 꼬리 오차를 털어 낸다. 14 ÷ (1 × 14/17) 이 16.9999… 로 나오면
        // 내림했을 때 하루가 통째로 사라진다.
        return DecimalQuantity.round(remaining / dailyBurn, scale: 4)
    }

    /// 예상 소진일. 날짜 경계는 자정 기준으로 맞춘다.
    public static func projectedRunOutDate(
        remaining: Decimal,
        dailyScheduledQuantity: Decimal,
        adherence: Decimal?,
        from date: Date,
        calendar: Calendar = .current
    ) -> Date? {

        guard let days = projectedDaysRemaining(
            remaining: remaining,
            dailyScheduledQuantity: dailyScheduledQuantity,
            adherence: adherence
        ) else { return nil }

        let wholeDays = DecimalQuantity.floorToInt(days)
        return calendar.date(byAdding: .day, value: wholeDays, to: calendar.startOfDay(for: date))
    }

    // MARK: - 진료일까지 모자란 날

    /// 다음 진료까지 며칠치가 모자라는지.
    ///
    /// 부족 알림은 약별로 따로 보내지 않고, 이 값이 나온 약들을 묶어 한 번만 알린다:
    /// "다음 진료(9/12)까지 로라제팜이 4일 모자라요."
    ///
    /// - Returns: 모자란 날 수(1 이상). 충분하거나 예측할 수 없으면 nil.
    public static func shortfallBeforeAppointment(
        remaining: Decimal,
        dailyScheduledQuantity: Decimal,
        adherence: Decimal?,
        from date: Date,
        nextVisit: Date,
        calendar: Calendar = .current
    ) -> Int? {

        let today = calendar.startOfDay(for: date)
        let visit = calendar.startOfDay(for: nextVisit)
        guard let daysNeeded = calendar.dateComponents([.day], from: today, to: visit).day,
              daysNeeded > 0
        else { return nil }

        guard let covered = projectedDaysRemaining(
            remaining: remaining,
            dailyScheduledQuantity: dailyScheduledQuantity,
            adherence: adherence
        ) else { return nil }

        let shortfall = Decimal(daysNeeded) - covered
        guard shortfall > 0 else { return nil }
        return max(1, DecimalQuantity.ceilToInt(shortfall))
    }

    // MARK: - 한 번에 묶어 보기

    /// 화면 한 줄에 필요한 값을 한 번에 계산한 결과.
    public struct Snapshot: Hashable, Sendable {
        public let medicationID: UUID
        public let remaining: Decimal
        public let dailyScheduledQuantity: Decimal
        public let adherence: Decimal?
        public let daysRemaining: Decimal?
        public let runOutDate: Date?
        public let shortfallDays: Int?

        public init(
            medicationID: UUID,
            remaining: Decimal,
            dailyScheduledQuantity: Decimal,
            adherence: Decimal?,
            daysRemaining: Decimal?,
            runOutDate: Date?,
            shortfallDays: Int?
        ) {
            self.medicationID = medicationID
            self.remaining = remaining
            self.dailyScheduledQuantity = dailyScheduledQuantity
            self.adherence = adherence
            self.daysRemaining = daysRemaining
            self.runOutDate = runOutDate
            self.shortfallDays = shortfallDays
        }
    }

    /// 약 하나의 재고 상태를 한 번에 계산한다.
    public static func snapshot(
        medicationID: UUID,
        schedules: [Schedule],
        stockEvents: [StockEvent],
        doseEvents: [DoseEvent],
        nextVisit: Date? = nil,
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> Snapshot {

        let mine = schedules.filter { $0.medicationID == medicationID }
        let daily = mine.dailyScheduledQuantity()

        // 지역 이름이 static 메서드 이름을 가리지 않도록 전부 타입 이름으로 부른다.
        let remainingCount = InventoryCalculator.remaining(
            for: medicationID,
            stockEvents: stockEvents,
            doseEvents: doseEvents,
            asOf: asOf,
            calendar: calendar
        )

        let rate = InventoryCalculator.adherenceRate(
            doseEvents: doseEvents,
            medicationID: medicationID,
            last28DaysEndingAt: asOf,
            calendar: calendar
        )

        let days = InventoryCalculator.projectedDaysRemaining(
            remaining: remainingCount,
            dailyScheduledQuantity: daily,
            adherence: rate
        )

        let runOut = InventoryCalculator.projectedRunOutDate(
            remaining: remainingCount,
            dailyScheduledQuantity: daily,
            adherence: rate,
            from: asOf,
            calendar: calendar
        )

        let shortfall: Int? = nextVisit.flatMap { visit in
            InventoryCalculator.shortfallBeforeAppointment(
                remaining: remainingCount,
                dailyScheduledQuantity: daily,
                adherence: rate,
                from: asOf,
                nextVisit: visit,
                calendar: calendar
            )
        }

        return Snapshot(
            medicationID: medicationID,
            remaining: remainingCount,
            dailyScheduledQuantity: daily,
            adherence: rate,
            daysRemaining: days,
            runOutDate: runOut,
            shortfallDays: shortfall
        )
    }
}
