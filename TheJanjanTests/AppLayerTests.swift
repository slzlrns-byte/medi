import XCTest
import SwiftData
import UIKit
import UserNotifications
import JanjanCore
@testable import TheJanjan

/// 앱 계층만 얇게 확인한다.
/// 재고·복약률 같은 순수 로직은 Packages/JanjanCore 의 `swift test` 가 이미 검증했다.
@MainActor
final class AppLayerTests: XCTestCase {

    // MARK: - 레코드 ↔ 코어 모델 왕복

    func testMedicationRecordRoundTrip() {
        let core = Medication(
            name: "쿠에티아핀",
            strengthText: "25mg",
            form: .tablet,
            kind: .scheduled,
            status: .active,
            note: "저녁에만",
            catalogID: "quetiapine-25",
            purposeLine: "잠들기 쉽게"
        )
        let restored = MedicationRecord.make(from: core).core
        XCTAssertEqual(restored, core)
    }

    func testDoseEventRecordRoundTripKeepsHalfTablet() {
        let core = DoseEvent(
            medicationID: UUID(),
            scheduledAt: Date(timeIntervalSince1970: 1_755_000_000),
            actualAt: Date(timeIntervalSince1970: 1_755_003_600),
            status: .taken,
            source: .notificationAction,
            quantity: Decimal(string: "0.5") ?? 1,
            kind: .scheduled,
            slotKey: DoseSlot.bedtime.storageKey
        )
        let restored = DoseEventRecord.make(from: core).core
        XCTAssertEqual(restored, core)
        XCTAssertEqual(restored.quantity, Decimal(string: "0.5"))
    }

    func testStockEventRecordDistinguishesRefillFromCorrection() {
        let medicationID = UUID()
        let refill = StockEvent.refill(medicationID: medicationID, quantity: 28, at: Date())
        let correction = StockEvent.correction(medicationID: medicationID, setTo: 17, at: Date())

        XCTAssertEqual(StockEventRecord.make(from: refill).core, refill)
        XCTAssertEqual(StockEventRecord.make(from: correction).core, correction)
        XCTAssertTrue(StockEventRecord.make(from: correction).core.isCorrection)
        XCTAssertFalse(StockEventRecord.make(from: refill).core.isCorrection)
    }

    func testScheduleRecordRoundTrip() {
        let core = Schedule(
            medicationID: UUID(),
            slot: .custom(TimeOfDay(hour: 6, minute: 45)),
            weekdays: [.monday, .wednesday, .friday],
            dosePerIntake: Decimal(string: "0.5") ?? 1
        )
        let restored = ScheduleRecord.make(from: core).core
        XCTAssertEqual(restored, core)
    }

    func testCheckInRecordRoundTrip() {
        let core = CheckIn(
            date: Date(timeIntervalSince1970: 1_755_000_000),
            mood: CheckIn.Mood(-2),
            energy: 2,
            anxiety: 4,
            emotionWords: ["anxious", "worn_out"],
            sleepMinutes: 320,
            sleepQuality: .poor,
            dreamed: true,
            activities: ["외출"],
            note: "오후에 조금 나아졌어요",
            updatedAt: Date(timeIntervalSince1970: 1_755_010_000)
        )
        let restored = CheckInRecord.make(from: core).core
        XCTAssertEqual(restored, core)
    }

    func testSymptomEntryRecordRoundTrip() {
        let core = SymptomEntry(
            symptomID: "anxiety_restless",
            severity: 7,
            startedAt: Date(timeIntervalSince1970: 1_755_000_000),
            durationMinutes: 40,
            contextTags: ["사람 많은 곳"],
            source: .watch
        )
        let restored = SymptomEntryRecord.make(from: core).core
        XCTAssertEqual(restored, core)
    }

    // MARK: - 저장소가 실제로 열리는지

    func testInMemoryContainerAcceptsEveryModel() throws {
        let schema = Schema(JanjanSchema.allModels)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        context.insert(MedicationRecord.make(from: SampleData.quetiapine))
        context.insert(ScheduleRecord.make(from: Schedule(medicationID: SampleData.quetiapine.id, slot: .bedtime)))
        context.insert(DoseEventRecord.make(from: DoseEvent(medicationID: SampleData.quetiapine.id, scheduledAt: Date())))
        context.insert(StockEventRecord.make(from: .refill(medicationID: SampleData.quetiapine.id, quantity: 14, at: Date())))
        context.insert(CheckInRecord.make(from: CheckIn(date: Date(), mood: CheckIn.Mood(0))))
        context.insert(SymptomEntryRecord.make(from: SymptomEntry(symptomID: "headache", severity: 2, startedAt: Date())))

        try context.save()

        let medications = try context.fetch(FetchDescriptor<MedicationRecord>())
        XCTAssertEqual(medications.count, 1)
        XCTAssertEqual(medications.first?.core.name, "쿠에티아핀")
    }

    // MARK: - 디자인 토큰이 UIColor 로 살아 나오는지

    func testEveryTokenBecomesAUIColor() {
        for token in JanjanColor.allCases {
            XCTAssertNotNil(UIColor(janjanHex: token.lightHex), "\(token) 라이트")
            XCTAssertNotNil(UIColor(janjanHex: token.darkHex), "\(token) 다크")
        }
        XCTAssertNil(UIColor(janjanHex: "not-a-color"))
    }

    // MARK: - 알림 액션 파싱

    func testNotificationCategoryAndActionIdentifiers() {
        XCTAssertEqual(DoseNotification.categoryID, "DOSE_REMINDER")
        XCTAssertEqual(DoseNotification.actionTaken, "DOSE_TAKEN")
        XCTAssertEqual(DoseNotification.actionSkipped, "DOSE_SKIPPED")
        XCTAssertEqual(DoseNotification.actionSnooze, "DOSE_SNOOZE")
        XCTAssertEqual(DoseNotification.snoozeInterval, 30 * 60)

        XCTAssertEqual(DoseNotification.doseAction(for: DoseNotification.actionTaken), .taken)
        XCTAssertEqual(DoseNotification.doseAction(for: DoseNotification.actionSkipped), .skipped)
        XCTAssertEqual(DoseNotification.doseAction(for: DoseNotification.actionSnooze), .snooze)
        XCTAssertNil(DoseNotification.doseAction(for: UNNotificationDefaultActionIdentifier))
    }
}

/// 늦게 답한 알림이 어느 날에 붙는가.
///
/// 여기가 어긋나면 두 번 먹은 것이 한 번으로 남는다. 아침 약을 밤에 뒤늦게 기록했는데
/// 그것이 '내일 아침' 줄에 적히면, 다음 날 진짜로 아침 약을 먹고 기록할 때 그 줄을
/// 덮어쓴다. 재고는 한 알만 줄고, 오늘 아침은 영영 미기록으로 남는다.
/// CloudKit 제약을 실제로 확인한다.
///
/// 메모리 저장소로만 열어 보는 테스트는 이 제약을 확인하지 못한다.
/// "모든 속성에 기본값" · "unique 금지" · "관계 금지" 는 `cloudKitDatabase` 를
/// 지정했을 때만 검사되고, 어기면 던지는 것이 아니라 **그 자리에서 죽는다.**
/// 그러니 이 테스트가 할 일은 크래시하지 않고 끝나는 것 하나뿐이다.
/// (iCloud 를 못 쓰는 러너에서는 그냥 throw 하고, 그건 통과로 본다.)
final class CloudKitSchemaTests: XCTestCase {

    func testEveryModelSurvivesACloudKitConfiguration() throws {
        let schema = Schema(JanjanSchema.allModels)
        let configuration = ModelConfiguration(
            "JanjanCloudKitSchemaCheck",
            schema: schema,
            cloudKitDatabase: .private(Janjan.cloudKitContainerID)
        )
        _ = try? ModelContainer(for: schema, configurations: configuration)
    }
}

@MainActor
final class PlannedDayTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute)
        ) ?? Date(timeIntervalSince1970: 0)
    }

    private func plannedDay(at moment: Date, slot: TimeOfDay) -> Date {
        DoseRecorder.plannedDay(near: moment, scheduleTime: slot, calendar: calendar)
    }

    func testLateAnswerStaysOnToday() {
        // 아침 8시 약을 그날 밤 9시에 기록. 13시간 늦었지만 오늘 것이다.
        let chosen = plannedDay(at: date(17, 21), slot: TimeOfDay(hour: 8, minute: 0))
        XCTAssertEqual(chosen, calendar.startOfDay(for: date(17, 12)))
    }

    func testVeryLateAnswerNeverJumpsToTomorrow() {
        // 자정 직전이라 내일 8시가 더 가깝지만, 아직 오지 않은 예정분에는 붙이지 않는다.
        let chosen = plannedDay(at: date(17, 23, 30), slot: TimeOfDay(hour: 8, minute: 0))
        XCTAssertEqual(chosen, calendar.startOfDay(for: date(17, 12)))
    }

    func testAfterMidnightAnswerGoesBackToYesterday() {
        // 어젯밤 23:50 취침약 알림에 00:05 에 답했다.
        let chosen = plannedDay(at: date(18, 0, 5), slot: TimeOfDay(hour: 23, minute: 50))
        XCTAssertEqual(chosen, calendar.startOfDay(for: date(17, 12)))
    }

    func testSlightlyEarlyAnswerCountsAsToday() {
        // 알림이 울리기 20분 전에 미리 먹고 눌렀다.
        let chosen = plannedDay(at: date(17, 22, 10), slot: TimeOfDay(hour: 22, minute: 30))
        XCTAssertEqual(chosen, calendar.startOfDay(for: date(17, 12)))
    }

    func testOnTimeAnswer() {
        let chosen = plannedDay(at: date(17, 8, 2), slot: TimeOfDay(hour: 8, minute: 0))
        XCTAssertEqual(chosen, calendar.startOfDay(for: date(17, 12)))
    }
}
