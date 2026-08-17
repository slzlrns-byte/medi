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
