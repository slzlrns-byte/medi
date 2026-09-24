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

        // **기준점이 하나도 없으면 가장 이른 재고 사건이 기준점이다.**
        //
        // 등록 폼은 정정을 남기지만, 스캔 같은 다른 길이나 옛 빌드로 들어온
        // 약에는 정정이 없을 수 있다. 그러면 셈이 0 에서 시작해 **그 앞의
        // 복용까지 전부 빼** 버린다 -
        // 8/1 에 등록하고 한 달 매일 먹은 뒤 8/31 에 28정을 받으면
        // 0 − 30 + 28 = −2정이 됐다. 두 달이면 −32정이다(QA 2026-09-21).
        //
        // 앱이 개수를 처음 알게 된 순간보다 앞선 복용은 **앱이 존재조차
        // 모르던 약**이라 셀 근거가 없다. 그 순간을 암묵적 기준점으로 삼는다.
        // 정정이 하나라도 있으면 그쪽이 기준점이므로 여기는 지나간다.
        if !steps.contains(where: { if case .correction = $0.step { return true } else { return false } }),
           let firstStock = steps.first(where: {
               if case .consumption = $0.step { return false } else { return true }
           })?.date {
            steps.removeAll { entry in
                if case .consumption = entry.step { return entry.date < firstStock }
                return false
            }
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
            // **앱이 채운 미기록은 답이 아니다**(QA 2026-09-22). 요일을 넓히면
            // 채우기가 지난 4주의 새 요일을 전부 `.automatic` 미기록으로 채우는데,
            // 그것을 분모에 넣으면 12/12 가 12/28 로 내려가 소진 예측이 두 배로
            // 늘고 "부족한 약 없음" 이 뜬다 - 실제로는 6일 모자란다. 물어볼
            // 자리로 만든 줄이지 안 먹었다는 기록이 아니므로 뺀다. 사용자가
            // 직접 고른 "기억나지 않아요" 는 답이라 그대로 센다.
            if event.status == .unrecorded, event.source == .automatic { continue }
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

        let total = latest.count
        guard total > 0 else { return nil }
        let taken = latest.values.filter { $0.status == .taken }.count
        return Decimal(taken) / Decimal(total)
    }

    // MARK: - 진료 기준 복약률

    /// 한 진료를 기준으로 잰 복약률. 분모는 그 진료 뒤 지금까지 스케줄이
    /// 예정한 개수다.
    public struct PrescriptionAdherence: Hashable, Sendable {

        /// 약 하나의 몫.
        public struct Item: Hashable, Sendable {
            public let medicationID: UUID
            /// 그 진료에서 받은 알 수.
            public let received: Decimal
            /// 지금까지 먹었어야 할 알 수.
            public let expected: Decimal
            /// 먹었다고 기록된 알 수.
            public let taken: Decimal
            /// 0…1.
            public let rate: Decimal
        }

        /// 진료 받은 시각.
        public let visitDate: Date
        /// 분모가 선 구간. `[windowStart, windowEnd)`, **시각 단위**. 진료 시각에서
        /// 열려 지금(또는 처방 끝·다음 진료)에서 닫힌다. 종이의 "복용 N회" 줄이
        /// 같은 창을 세야 한 구역 안의 두 숫자가 어긋나지 않는다.
        public let windowStart: Date
        public let windowEnd: Date
        /// 창이 걸친 날 수(진료일부터 창 끝 날까지).
        public let elapsedDays: Int
        /// 약별 몫. 화면과 종이가 약마다 따로 적을 때 쓴다.
        public let items: [Item]
        /// 그 진료에서 받은 알 수 합(정기 약만).
        public let received: Decimal
        /// 지금까지 먹었어야 할 알 수 합.
        public let expected: Decimal
        /// 먹었다고 기록된 알 수 합.
        public let taken: Decimal
        /// **약별 복약률의 평균**. 0…1.
        ///
        /// 알 수로 가중하지 않는다(사용자 결정 2026-09-21) - 그러면 하루 세
        /// 번 먹는 약이 한 번 먹는 약보다 세 배 무거워진다. 약 두 개 중
        /// 하나를 꼬박 먹고 하나를 통째로 건너뛰었으면 그건 50% 다.
        public let rate: Decimal
    }

    /// **복약률은 "오늘 이 시각까지 먹었어야 하는 개수" 로 센다**(사용자 결정
    /// 2026-09-22 저녁).
    ///
    ///     창 = [진료 시각, min(지금, 진료 시각 + 처방일수, 다음 진료 시각, 중단 시각))
    ///     먹었어야 할 = 창 안에 **예정 시각이 든** 스케줄 칸의 개수 합
    ///     약별 복약률 = 창 안의 복용 기록 알 수 ÷ 먹었어야 할
    ///     전체 복약률 = 약별 복약률의 **평균**
    ///
    /// **날이 아니라 시각으로 자른다.** 오늘 진료를 받았으면 그날 아침 약은
    /// 이전 처방의 몫이고, 진료 뒤 저녁 약부터 새 처방의 몫이다. 오늘 아직
    /// 오지 않은 시간대는 세지 않는다 - 오후 3시에 보면 자기전 약은 분모에
    /// 없다. 그래서 진료 당일에도 첫 시간대가 지나면 바로 숫자가 선다.
    ///
    /// 한때 받은 알 수 ÷ 처방일수 × 지난 날로 셌다(2026-09-21). 요일을 고쳐도
    /// 흔들리지 않는 장점이 있었지만, 하루 두 번 먹는 약이나 여유분을 더 받은
    /// 약에서 "먹었어야 하는 개수" 와 어긋났고, 달력·"기록 없이 지나간 시간대"
    /// 와 다른 셈법이었다. 지금은 앱 어디서나 스케줄이 예정을 정한다. 대신
    /// 요일을 고치면 지난 복약률도 새 요일로 다시 계산된다 - 고치기 폼이 그
    /// 사실을 말한다.
    ///
    /// **받은 알 수는 분모가 아니다.** 어느 약이 이 진료에 속하는지(보충이
    /// 있는 약) 정하는 데만 쓴다. 필요시 약은 빼고 센다 - 안 먹는 것이 정상이라
    /// 분모에 넣으면 비율이 근거 없이 내려간다.
    ///
    /// **알 수로 가중하지 않는다.** 합으로 나누면 하루 세 번 먹는 약이 한 번
    /// 먹는 약보다 세 배 무거워진다. 약 두 개 중 하나를 꼬박 먹고 하나를
    /// 통째로 건너뛰었으면 그건 50% 다(사용자 결정 2026-09-21).
    ///
    /// **중단한 약도 중단 전까지는 센다.** 끊은 뒤로는 분모가 더 늘지 않는다.
    /// 끊었다 다시 먹는 약의 쉰 구간 `[stoppedAt, resumedAt)` 은 의사가 시킨
    /// 휴약이라 분모에서도 분자에서도 뺀다.
    ///
    /// **기록하지 않은 칸은 안 먹은 것으로 센다.** 나중에 그 칸을 채우면
    /// 분자가 올라가 비율이 따라 오른다.
    ///
    /// - Returns: 진료 기록이 없거나, 받은 약이 없거나, 아직 지난 시간대가
    ///   하나도 없으면 nil. 그때는 그 앞 진료로 물러나고, 그것도 없으면
    ///   화면이 안내 문구를 대신 보여 준다.
    public static func prescriptionAdherence(
        prescriptions: [Prescription],
        schedules: [Schedule] = [],
        stockEvents: [StockEvent],
        doseEvents: [DoseEvent],
        medications: [Medication],
        medicationID: UUID? = nil,
        asOf: Date,
        calendar: Calendar = .current
    ) -> PrescriptionAdherence? {

        // 다녀온 진료를 **나중 것부터** 훑는다. 셀 수 있는 진료가 나올 때까지
        // 물러난다 - 방금 적은 오늘 진료는 지난 시간대가 아직 없을 수 있고,
        // 약을 지운 진료는 보충이 없다(QA 2026-09-22). 이전 진료의 창은
        // 그 다음 진료 시각에서 닫힌다: 진료 전 아침 약은 이전 처방의 몫이다.
        let candidates = prescriptions
            .filter { $0.visitDate <= asOf }
            .filter { $0.daysSupplied > 0 }
            .sorted { $0.visitDate > $1.visitDate }
        var laterVisit: Date?
        for visit in candidates {
            let until = min(asOf, laterVisit ?? asOf)
            if let result = adherence(
                for: visit,
                until: until,
                schedules: schedules,
                stockEvents: stockEvents,
                doseEvents: doseEvents,
                medications: medications,
                medicationID: medicationID,
                calendar: calendar
            ) {
                return result
            }
            laterVisit = visit.visitDate
        }
        return nil
    }

    /// 스케줄이 `[start, end)` 안에 예정한 개수 합. 쉰 구간은 뺀다.
    ///
    /// `Schedule.isActive(on:)` 가 요일·시작일·종료일을 본다 - 등록일 앞에는
    /// 계획이 없으므로 그 날들은 저절로 0 이다. 오늘의 아직 안 온 시간대는
    /// `end`(지금) 뒤라 들지 않는다.
    static func plannedQuantity(
        schedules: [Schedule],
        from start: Date,
        to end: Date,
        excluding pause: (start: Date, end: Date)? = nil,
        calendar: Calendar
    ) -> Decimal {
        guard start < end, !schedules.isEmpty else { return 0 }
        var total: Decimal = 0
        var day = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)
        while day <= lastDay {
            for schedule in schedules where schedule.isActive(on: day, calendar: calendar) {
                let at = schedule.timeOfDay.date(on: day, calendar: calendar)
                guard at >= start, at < end else { continue }
                if let pause, at >= pause.start, at < pause.end { continue }
                total += schedule.dosePerIntake
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return total
    }

    /// 진료 하나를 기준으로 낸 복약률. 셀 근거가 없으면 nil.
    private static func adherence(
        for visit: Prescription,
        until: Date,
        schedules: [Schedule],
        stockEvents: [StockEvent],
        doseEvents: [DoseEvent],
        medications: [Medication],
        medicationID: UUID?,
        calendar: Calendar
    ) -> PrescriptionAdherence? {

        // 처방 단위의 창. 처방일수를 넘겨서는 자라지 않는다 - 받은 약이
        // 그만큼뿐이다.
        let supplyEnd = calendar.date(byAdding: .day, value: visit.daysSupplied, to: visit.visitDate) ?? until
        let prescriptionEnd = min(until, supplyEnd)
        guard visit.visitDate < prescriptionEnd else { return nil }
        let elapsed = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: visit.visitDate),
            to: calendar.startOfDay(for: prescriptionEnd)
        ).day ?? 0

        // 필요시 약은 빼고, 이 진료에 매인 보충만 약별로 모은다.
        var byID: [UUID: Medication] = [:]
        for medication in medications { byID[medication.id] = medication }

        var received: [UUID: Decimal] = [:]
        for event in stockEvents where event.prescriptionID == visit.id {
            guard case .refill(let quantity) = event.kind, quantity > 0 else { continue }
            if let medicationID, event.medicationID != medicationID { continue }
            if byID[event.medicationID]?.kind == .asNeeded { continue }
            received[event.medicationID, default: 0] += quantity
        }
        guard !received.isEmpty else { return nil }

        // 이 진료에 매인 약들의 복용 기록만 모은다. 기기 간 중복은 하나로 묶는다.
        var recordsByID: [UUID: [DoseEvent]] = [:]
        for event in collapsedScheduledDoses(doseEvents, calendar: calendar) {
            guard event.status == .taken else { continue }
            guard received[event.medicationID] != nil else { continue }
            recordsByID[event.medicationID, default: []].append(event)
        }

        var items: [PrescriptionAdherence.Item] = []
        for (id, quantity) in received {
            let medication = byID[id]

            // 약마다 창을 따로 연다.
            // · 앱이 그 약을 알기 전(등록 전)은 세지 않는다 - 그 날들에는
            //   기록이 있을 수가 없다(QA 2026-09-22).
            // · 끊은 약은 끊은 시각 앞에서 멈춘다.
            var windowStart = visit.visitDate
            if let createdAt = medication?.createdAt {
                windowStart = max(windowStart, createdAt)
            }
            var windowEnd = prescriptionEnd
            if medication?.status == .stopped, let stoppedAt = medication?.stoppedAt {
                windowEnd = min(windowEnd, stoppedAt)
            }
            guard windowStart < windowEnd else { continue }

            var pause: (start: Date, end: Date)?
            if medication?.status == .active,
               let stoppedAt = medication?.stoppedAt,
               let resumedAt = medication?.resumedAt {
                pause = (stoppedAt, resumedAt)
            }

            let expected = plannedQuantity(
                schedules: schedules.filter { $0.medicationID == id },
                from: windowStart,
                to: windowEnd,
                excluding: pause,
                calendar: calendar
            )
            guard expected > 0 else { continue }

            // **분자도 분모와 같은 창, 같은 축(예정 시각)으로 본다.** 어젯밤
            // 22:30 약을 00:10 에 먹었어도 그것은 어젯밤 줄이다 - `DayPlan` 의
            // 규칙이 여기서도 그대로 선다. (재고는 실제로 준 시점이 중요하므로
            // `effectiveDate` 를 쓴다.)
            let taken = (recordsByID[id] ?? []).reduce(Decimal(0)) { sum, event in
                let when = event.kind == .scheduled ? event.scheduledAt : event.effectiveDate
                guard when >= windowStart, when < windowEnd else { return sum }
                if let pause, when >= pause.start, when < pause.end { return sum }
                return sum + event.quantity
            }

            // 100% 를 넘겨 적지 않는다. 더 먹었다는 뜻일 수도 있지만 대개는
            // 기록이 겹친 것이고, "복약률 120%" 는 읽는 사람에게 오류로 보인다.
            let rate = min(max(DecimalQuantity.round(taken / expected, scale: 4), 0), 1)
            items.append(PrescriptionAdherence.Item(
                medicationID: id,
                received: DecimalQuantity.round(quantity, scale: 2),
                expected: DecimalQuantity.round(expected, scale: 2),
                taken: DecimalQuantity.round(taken, scale: 2),
                rate: rate
            ))
        }
        guard !items.isEmpty else { return nil }

        // **약별 비율의 평균.** 알 수로 가중하지 않는다.
        let average = items.reduce(Decimal(0)) { $0 + $1.rate } / Decimal(items.count)

        return PrescriptionAdherence(
            visitDate: visit.visitDate,
            windowStart: visit.visitDate,
            windowEnd: prescriptionEnd,
            elapsedDays: elapsed,
            items: items.sorted { $0.medicationID.uuidString < $1.medicationID.uuidString },
            received: DecimalQuantity.round(items.reduce(Decimal(0)) { $0 + $1.received }, scale: 2),
            expected: DecimalQuantity.round(items.reduce(Decimal(0)) { $0 + $1.expected }, scale: 2),
            taken: DecimalQuantity.round(items.reduce(Decimal(0)) { $0 + $1.taken }, scale: 2),
            rate: DecimalQuantity.round(average, scale: 4)
        )
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
