import Foundation

/// 화면을 그려 보기 위한 예시 데이터. 실제 저장소가 비어 있을 때만 쓴다.
///
/// 실존 처방이 아니라 설계 문서의 예시(설계 05절 · 07절)를 그대로 옮긴 것이다.
public enum SampleData {

    public static let calendar = Calendar(identifier: .gregorian)

    public static let quetiapine = Medication(
        id: UUID(uuidString: "11111111-1111-4111-8111-111111111111") ?? UUID(),
        name: "쿠에티아핀",
        strengthText: "25mg",
        form: .tablet,
        kind: .scheduled,
        purposeLine: "잠들기 쉽게"
    )

    public static let lamotrigine = Medication(
        id: UUID(uuidString: "22222222-2222-4222-8222-222222222222") ?? UUID(),
        name: "라모트리진",
        strengthText: "100mg",
        form: .tablet,
        kind: .scheduled,
        purposeLine: "기분이 크게 흔들리지 않게"
    )

    public static let escitalopram = Medication(
        id: UUID(uuidString: "33333333-3333-4333-8333-333333333333") ?? UUID(),
        name: "에스시탈로프람",
        strengthText: "10mg",
        form: .tablet,
        kind: .scheduled,
        purposeLine: "가라앉는 기분을 덜하게"
    )

    public static let lorazepam = Medication(
        id: UUID(uuidString: "44444444-4444-4444-8444-444444444444") ?? UUID(),
        name: "로라제팜",
        strengthText: "0.5mg",
        form: .tablet,
        kind: .asNeeded,
        purposeLine: "불안이 몰려올 때"
    )

    public static let medications: [Medication] = [
        escitalopram, lamotrigine, quetiapine, lorazepam
    ]

    public static let schedules: [Schedule] = [
        Schedule(medicationID: escitalopram.id, slot: .morning, dosePerIntake: 1),
        Schedule(medicationID: lamotrigine.id, slot: .bedtime, dosePerIntake: 1),
        Schedule(medicationID: quetiapine.id, slot: .bedtime, dosePerIntake: Decimal(string: "0.5") ?? 1)
    ]

    /// 설계 05절의 예시: 8/1 에 28일분 보충.
    public static func stockEvents(referenceDate: Date) -> [StockEvent] {
        let refillDate = calendar.date(byAdding: .day, value: -16, to: referenceDate) ?? referenceDate
        return [
            .refill(medicationID: escitalopram.id, quantity: 28, at: refillDate),
            .refill(medicationID: lamotrigine.id, quantity: 28, at: refillDate),
            .refill(medicationID: quetiapine.id, quantity: 14, at: refillDate),
            .refill(medicationID: lorazepam.id, quantity: 10, at: refillDate)
        ]
    }

    /// 지난 16일치 복용 기록. 대부분 복용했고 며칠은 건너뛰거나 비어 있다.
    public static func doseEvents(referenceDate: Date) -> [DoseEvent] {
        var events: [DoseEvent] = []
        for offset in stride(from: 16, through: 1, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: referenceDate) else { continue }

            let status: DoseEvent.Status
            switch offset {
            case 5, 11: status = .skipped
            case 8: status = .unrecorded
            default: status = .taken
            }

            let morning = TimeOfDay(hour: 8, minute: 0).date(on: day, calendar: calendar)
            events.append(
                DoseEvent(
                    medicationID: escitalopram.id,
                    scheduledAt: morning,
                    actualAt: status == .taken ? morning : nil,
                    status: status,
                    quantity: 1,
                    slotKey: DoseSlot.morning.storageKey
                )
            )

            let night = TimeOfDay(hour: 22, minute: 30).date(on: day, calendar: calendar)
            events.append(
                DoseEvent(
                    medicationID: lamotrigine.id,
                    scheduledAt: night,
                    actualAt: status == .taken ? night : nil,
                    status: status,
                    quantity: 1,
                    slotKey: DoseSlot.bedtime.storageKey
                )
            )
            events.append(
                DoseEvent(
                    medicationID: quetiapine.id,
                    scheduledAt: night,
                    actualAt: status == .taken ? night : nil,
                    status: status,
                    quantity: Decimal(string: "0.5") ?? 1,
                    slotKey: DoseSlot.bedtime.storageKey
                )
            )
        }
        return events
    }

    public static func prescription(referenceDate: Date) -> Prescription {
        Prescription(
            visitDate: calendar.date(byAdding: .day, value: -16, to: referenceDate) ?? referenceDate,
            daysSupplied: 28,
            nextVisitDate: calendar.date(byAdding: .day, value: 12, to: referenceDate),
            clinicNote: "다음 진료 때 아침 졸림 이야기하기",
            medicationIDs: medications.map(\.id)
        )
    }

    public static func medication(id: UUID) -> Medication? {
        medications.first { $0.id == id }
    }

    /// 워치에 보낼 오늘 요약을 예시 데이터로 만든다.
    public static func watchSnapshot(referenceDate: Date = Date()) -> WatchSnapshot {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.setLocalizedDateFormatFromTemplate("Md")

        let lines: [WatchSnapshot.SlotLine] = [
            WatchSnapshot.SlotLine(
                slotKey: DoseSlot.morning.storageKey,
                labelKo: DoseSlot.morning.labelKo,
                timeText: TimeOfDay(hour: 8, minute: 0).description,
                medicationNames: [escitalopram.name],
                isCompleted: true
            ),
            WatchSnapshot.SlotLine(
                slotKey: DoseSlot.bedtime.storageKey,
                labelKo: DoseSlot.bedtime.labelKo,
                timeText: TimeOfDay(hour: 22, minute: 30).description,
                medicationNames: [lamotrigine.name, quetiapine.name],
                isCompleted: false
            )
        ]

        return WatchSnapshot(
            generatedAt: referenceDate,
            dateText: formatter.string(from: referenceDate),
            slots: lines,
            remainingCountToday: 2
        )
    }
}
