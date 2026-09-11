#if DEBUG
import Foundation
import SwiftData
import JanjanCore

/// 화면을 찍기 위해 예시 기록을 심는다.
///
/// **`#if DEBUG` 안에만 있다.** 출시 빌드에서는 컴파일조차 되지 않으므로 사용자의
/// 저장소에 예시 데이터가 섞여 들어갈 길이 없다(심사 2.1 "체험용 샘플 데이터 없음").
///
/// 실행 인자 `-JanjanSeedDemoData` 가 있을 때만 돈다. UI 테스트가 그 인자를 준다.
/// 개발자에게 맥이 없어서 시뮬레이터를 눈으로 볼 수 없기 때문에, CI 의 macOS 러너가
/// 이 데이터를 심은 앱을 띄우고 화면을 찍어 보내 준다.
enum DemoSeed {

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-JanjanSeedDemoData")
    }

    /// 저장소를 비우고 예시 기록으로 다시 채운다. 찍을 때마다 같은 그림이 나와야 한다.
    @MainActor
    static func apply(to context: ModelContext, now: Date = Date()) {
        MedicationStore.deleteEverything(in: context)

        for medication in SampleData.medications {
            context.insert(MedicationRecord.make(from: medication))
        }
        for schedule in SampleData.schedules {
            context.insert(ScheduleRecord.make(from: schedule))
        }
        for event in SampleData.stockEvents(referenceDate: now) {
            context.insert(StockEventRecord.make(from: event))
        }
        for event in SampleData.doseEvents(referenceDate: now) {
            // 어제·그제 아침은 기록 없이 지나간 것으로 남긴다 — "이틀 연속 빠트림" 을
            // 화면(지나간 시간대 안내·다시 세기 대조)이 어떻게 다루는지 찍기 위해서다.
            if isRecentMorningGap(event, now: now) { continue }
            context.insert(DoseEventRecord.make(from: event))
        }
        context.insert(PrescriptionRecord.make(from: SampleData.prescription(referenceDate: now)))

        seedCheckIns(context: context, now: now)
        seedSymptoms(context: context, now: now)
        seedNotes(context: context, now: now)
        seedDoseChanges(context: context, now: now)
        seedAsNeededDoses(context: context, now: now)

        try? context.save()
    }

    /// 어제(1)·그제(2)의 에스시탈로프람 아침 기록인가.
    private static func isRecentMorningGap(_ event: DoseEvent, now: Date) -> Bool {
        guard event.medicationID == SampleData.escitalopram.id,
              event.slotKey == DoseSlot.morning.storageKey else { return false }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: event.scheduledAt),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        return days == 1 || days == 2
    }

    /// 필요시(로라제팜) 복용 예시: 오늘 한 번, 사흘 전 두 번.
    /// 오늘 화면의 필요시 카드 이력과 리포트의 "필요시 복용" 구역이 이걸로 보인다.
    private static func seedAsNeededDoses(context: ModelContext, now: Date) {
        let calendar = Calendar.current
        var moments: [Date] = [now.addingTimeInterval(-60)]
        if let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now) {
            let day = calendar.startOfDay(for: threeDaysAgo)
            moments.append(day.addingTimeInterval(15 * 3600))
            moments.append(day.addingTimeInterval(20 * 3600 + 1800))
        }
        for at in moments {
            let event = DoseEvent(
                medicationID: SampleData.lorazepam.id,
                scheduledAt: at,
                actualAt: at,
                status: .taken,
                quantity: 1,
                kind: .asNeeded,
                slotKey: nil
            )
            context.insert(DoseEventRecord.make(from: event))
        }
    }

    /// 지난 2주의 기분. 오르내림이 있어야 "지난 기록" 이 한 줄짜리로 보이지 않는다.
    private static func seedCheckIns(context: ModelContext, now: Date) {
        let calendar = Calendar.current
        let scores = [0, -1, -2, -1, 0, 1, 0, -1, -2, -2, -1, 0, 1, 1]
        let notes = [
            "잠이 늦게 들었어요", nil, "회사에서 힘든 날", nil, nil,
            "오랜만에 산책했어요", nil, nil, "약 시간을 놓쳤어요", nil,
            nil, "조금 나은 것 같아요", nil, nil
        ]

        for (offset, score) in scores.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            // 꿈 3척도 화면을 확인하려면 예시가 몇 개는 있어야 한다. 매일 넣으면
            // "안 고르면 nil" 이라는 원칙이 화면에서 안 보이니 이틀만 채운다.
            let checkIn: CheckIn
            switch offset {
            case 0:
                // 오늘 기록에도 꿈을 반쯤 채워 둔다 - 화면 찍기(05-기록-펼침)가
                // 3척도 줄과 "안 적음" 상태를 같이 보여 주려면 오늘이어야 한다.
                checkIn = CheckIn(
                    date: calendar.startOfDay(for: day),
                    mood: CheckIn.Mood(score),
                    energy: max(1, min(5, 3 + score)),
                    anxiety: max(1, min(5, 3 - score)),
                    emotionWords: ["anxious", "worn_out"],
                    sleepMinutes: 6 * 60,
                    dreamed: true,
                    dreamVividness: 2,
                    // 술 칩이 켜진 모습도 화면 찍기에 보이게 한다.
                    activities: ["outdoors", "caffeine", "alcohol"],
                    note: notes.indices.contains(offset) ? notes[offset] : nil,
                    updatedAt: day
                )
            case 3:
                checkIn = CheckIn(
                    date: calendar.startOfDay(for: day),
                    mood: CheckIn.Mood(score),
                    energy: max(1, min(5, 3 + score)),
                    anxiety: max(1, min(5, 3 - score)),
                    emotionWords: offset % 3 == 0 ? ["anxious", "worn_out"] : [],
                    sleepMinutes: 6 * 60 + (offset % 4) * 30,
                    dreamed: true,
                    dreamVividness: 3,
                    nightmare: true,
                    dreamRecall: 3,
                    dreamNote: "쫓기는 꿈을 꿨어요",
                    activities: offset % 4 == 0 ? ["outdoors", "caffeine"] : ["work"],
                    note: notes.indices.contains(offset) ? notes[offset] : nil,
                    updatedAt: day
                )
            case 6:
                checkIn = CheckIn(
                    date: calendar.startOfDay(for: day),
                    mood: CheckIn.Mood(score),
                    energy: max(1, min(5, 3 + score)),
                    anxiety: max(1, min(5, 3 - score)),
                    emotionWords: offset % 3 == 0 ? ["anxious", "worn_out"] : [],
                    sleepMinutes: 6 * 60 + (offset % 4) * 30,
                    dreamed: true,
                    dreamVividness: 2,
                    dreamRecall: 1,
                    activities: offset % 4 == 0 ? ["outdoors", "caffeine"] : ["work"],
                    note: notes.indices.contains(offset) ? notes[offset] : nil,
                    updatedAt: day
                )
            default:
                checkIn = CheckIn(
                    date: calendar.startOfDay(for: day),
                    mood: CheckIn.Mood(score),
                    energy: max(1, min(5, 3 + score)),
                    anxiety: max(1, min(5, 3 - score)),
                    emotionWords: offset % 3 == 0 ? ["anxious", "worn_out"] : [],
                    sleepMinutes: 6 * 60 + (offset % 4) * 30,
                    activities: offset % 4 == 0 ? ["outdoors", "caffeine"] : ["work"],
                    note: notes.indices.contains(offset) ? notes[offset] : nil,
                    updatedAt: day
                )
            }
            context.insert(CheckInRecord.make(from: checkIn))
        }
    }

    private static func seedSymptoms(context: ModelContext, now: Date) {
        let calendar = Calendar.current
        let entries: [(String, Int, Int)] = [
            ("drowsiness", 6, 0), ("drowsiness", 4, 2), ("drowsiness", 5, 5),
            ("dry_mouth", 3, 1), ("anxiety_restless", 7, 3)
        ]
        for (symptomID, severity, daysAgo) in entries {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
            let entry = SymptomEntry(symptomID: symptomID, severity: severity, startedAt: day)
            context.insert(SymptomEntryRecord.make(from: entry))
        }
    }

    /// 이번에 넣은 "선생님이 말씀하신 것" 이 화면에서 어떻게 보이는지 확인하려면
    /// 예시가 하나는 있어야 한다.
    private static func seedNotes(context: ModelContext, now: Date) {
        guard let first = SampleData.medications.first else { return }
        let notes = [
            MedicationNote(
                medicationID: first.id,
                kind: .heardFromDoctor,
                text: "처음 며칠 졸릴 수 있는데 1~2주면 지나간다고 하심",
                symptomID: "drowsiness",
                createdAt: now
            ),
            MedicationNote(
                medicationID: first.id,
                kind: .heardFromDoctor,
                text: "술은 피하라고 하심",
                createdAt: now
            ),
            MedicationNote(
                medicationID: first.id,
                kind: .questionForDoctor,
                text: "아침에 더 졸린데 시간을 옮겨도 되는지",
                createdAt: now
            )
        ]
        for note in notes {
            context.insert(MedicationNoteRecord.make(from: note))
        }
    }

    /// 리포트 축에 놓일 용량 변경 예시. SampleData 의 에스시탈로프람이 지금 10mg 이라
    /// "5mg → 10mg" 로 넣으면 실제 처방과 어긋나지 않는다.
    private static func seedDoseChanges(context: ModelContext, now: Date) {
        let calendar = Calendar.current
        guard let changedAt = calendar.date(byAdding: .day, value: -9, to: now) else { return }
        let doseChange = DoseChange(
            medicationID: SampleData.escitalopram.id,
            changedAt: changedAt,
            fromText: "5mg",
            toText: "10mg"
        )
        context.insert(DoseChangeRecord.make(from: doseChange))
    }
}
#endif
