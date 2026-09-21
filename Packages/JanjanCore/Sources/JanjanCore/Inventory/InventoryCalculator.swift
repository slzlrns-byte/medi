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

    /// 모든 약의 **정기** 복용 사건에서 기기 간 중복을 하나로 묶는다.
    ///
    /// `collapsedDoses` 는 약 하나를 보고 `adherenceRate` 는 안에서 같은 일을
    /// 다시 한다. 종이의 "복용 N회 · 건너뜀 · 미기록" 만 원본을 세고 있어서,
    /// 같은 칸에 "복약률 100%" 와 "복용 2회 · 건너뜀 1회"(=66%)가 나란히
    /// 찍혔다(QA 2026-09-21). 그 자리가 쓸 집합을 여기서 만든다.
    ///
    /// 필요시(PRN)와 시간대 열쇠가 없는 줄은 묶지 않고 그대로 둔다 —
    /// `collapsedDoses` 와 같은 판단이다.
    static func collapsedScheduledDoses(
        _ doseEvents: [DoseEvent],
        calendar: Calendar = .current
    ) -> [DoseEvent] {

        var latest: [String: DoseEvent] = [:]
        var untouched: [DoseEvent] = []

        for event in doseEvents where event.kind == .scheduled {
            guard let slotKey = event.slotKey else {
                untouched.append(event)
                continue
            }
            let day = calendar.startOfDay(for: event.scheduledAt)
            let key = "\(event.medicationID.uuidString)|\(slotKey)|\(day.timeIntervalSinceReferenceDate)"
            if let kept = latest[key], isLater(kept, than: event) { continue }
            latest[key] = event
        }

        return untouched + Array(latest.values)
    }

    /// `DayPlan.latestEvent` 와 같은 순서 규칙. 둘이 어긋나면 화면과 재고가 다시 갈라진다.
    private static func isLater(_ lhs: DoseEvent, than rhs: DoseEvent) -> Bool {
        if lhs.effectiveDate != rhs.effectiveDate { return lhs.effectiveDate > rhs.effectiveDate }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    // MARK: - 이번 구간 (마지막 재고 사건 이후)

    /// 약 목록 행의 "17/28정 · 총 9정 복용" 을 위한 값.
    ///
    /// 구간의 시작은 **마지막 재고 사건**(보충이든 직접 정정이든)이다.
    /// `total` 은 그 직후의 잔여(= 구간 시작 총량), `consumed` 는 그 뒤로 줄어든 양.
    /// 세 값은 늘 `total - consumed = 지금 잔여` 로 맞아떨어진다 - 화면의 세 숫자가
    /// 서로 안 맞으면 사용자는 어느 것도 믿지 않게 된다.
    public struct CycleStatus: Hashable, Sendable {
        /// 구간 시작 시점의 총량.
        public let total: Decimal
        /// 구간 시작 이후 복용으로 줄어든 양(0 이상).
        public let consumed: Decimal
    }

    /// 마지막 재고 사건 이후의 총량·소비량. 재고 사건이 없으면 nil.
    public static func cycleStatus(
        for medicationID: UUID,
        stockEvents: [StockEvent],
        doseEvents: [DoseEvent],
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> CycleStatus? {

        let cycleStart = stockEvents
            .filter { $0.medicationID == medicationID && $0.occurredAt <= asOf }
            .map(\.occurredAt)
            .max()
        guard let cycleStart else { return nil }

        // remaining() 은 같은 시각이면 정정 → 보충 → 복용 순서로 계산하므로,
        // asOf 를 구간 시작 시각으로 주면 "그 사건 직후" 의 값이 나온다.
        let total = remaining(
            for: medicationID,
            stockEvents: stockEvents,
            doseEvents: doseEvents,
            asOf: cycleStart,
            calendar: calendar
        )
        let current = remaining(
            for: medicationID,
            stockEvents: stockEvents,
            doseEvents: doseEvents,
            asOf: asOf,
            calendar: calendar
        )
        return CycleStatus(
            total: max(total, 0),
            consumed: max(DecimalQuantity.round(total - current, scale: 4), 0)
        )
    }

    // MARK: - 복약률

    /// 기간 안의 복약률 = **복용함 ÷ (복용함 + 건너뜀)**.
    ///
    /// **모르는 날은 분모에서도 뺀다**(사용자 결정 2026-09-21).
    /// 미기록은 "안 먹었다" 가 아니라 "답이 없다" 이고, 그 둘을 섞으면 앱이
    /// 모르는 것을 안 먹은 것으로 바꿔 말하게 된다. 요일을 넓히기만 해도
    /// 앱이 지난 4주의 안 먹는 날을 "빠트림" 으로 채워 100% 가 42% 로
    /// 내려갔던 것이 그 결과다 - 한 번도 안 빠트린 사람의 숫자였다.
    ///
    /// 정기 예정분(`kind == .scheduled`)만 센다. 필요시 약은 안 먹는 게 정상이라
    /// 분모에 넣으면 복약률이 근거 없이 내려간다.
    ///
    /// **비율만 보이면 안 된다.** 5일 열어 5번 누른 사람도 100% 다. 그래서
    /// 화면과 종이는 `answeredDayCount` 를 함께 적어 "28일 중 12일 기록" 을
    /// 같이 보여 준다 - 비율에 표본이 붙어야 읽는 사람이 판단할 수 있다.
    ///
    /// - Returns: 0…1 사이 비율. 답한 사건이 하나도 없으면 nil.
    public static func adherenceRate(
        doseEvents: [DoseEvent],
        medicationID: UUID? = nil,
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> Decimal? {

        // 기기 간 중복(같은 약·시간대·날짜의 두 줄)은 가장 나중 것만 센다 —
        // remaining() 의 collapsedDoses 와 같은 규칙이다. 여기서만 원본을 그대로
        // 세면 분모가 부풀어 복약률이 실제와 다르게 나온다(QA 2026-09-10).
        var latest: [String: DoseEvent] = [:]

        for event in doseEvents {
            if let medicationID, event.medicationID != medicationID { continue }
            guard event.kind == .scheduled else { continue }
            let when = event.effectiveDate
            guard when >= start, when <= end else { continue }

            guard let slotKey = event.slotKey else {
                // 시간대 열쇠가 없으면 묶을 기준이 없다. 그대로 센다.
                latest[event.id.uuidString] = event
                continue
            }
            let day = calendar.startOfDay(for: event.scheduledAt)
            let key = "\(event.medicationID.uuidString)|\(slotKey)|\(day.timeIntervalSinceReferenceDate)"
            if let kept = latest[key], isLater(kept, than: event) { continue }
            latest[key] = event
        }

        // 답한 것만 센다. 미기록(앱이 채운 것과 사용자가 "기억나지 않아요" 를
        // 고른 것 둘 다)은 양쪽 어디에도 들어가지 않는다.
        let answered = latest.values.filter { $0.status == .taken || $0.status == .skipped }
        guard !answered.isEmpty else { return nil }
        let taken = answered.filter { $0.status == .taken }.count
        return Decimal(taken) / Decimal(answered.count)
    }

    /// 그 기간에 **답이 남은 날**이 며칠인지. 복약률 옆에 붙는 표본 크기다.
    ///
    /// 비율만 적으면 5일 열어 5번 누른 사람과 28일 내내 챙긴 사람이 똑같이
    /// 100% 로 보인다. 그 종이를 읽는 사람이 구별할 수 있어야 한다.
    public static func answeredDayCount(
        doseEvents: [DoseEvent],
        medicationID: UUID? = nil,
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> Int {
        var days: Set<Date> = []
        for event in doseEvents {
            if let medicationID, event.medicationID != medicationID { continue }
            guard event.kind == .scheduled else { continue }
            guard event.status == .taken || event.status == .skipped else { continue }
            let when = event.effectiveDate
            guard when >= start, when <= end else { continue }
            days.insert(calendar.startOfDay(for: event.scheduledAt))
        }
        return days.count
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
