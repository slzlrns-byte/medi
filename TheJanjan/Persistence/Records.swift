import Foundation
import SwiftData
import JanjanCore

// SwiftData 저장 모델.
//
// CloudKit private DB 와 함께 쓰려면 지켜야 하는 제약이 있다:
//   · 모든 속성에 기본값이 있어야 한다 (또는 옵셔널)
//   · @Attribute(.unique) 를 쓸 수 없다
//   · 관계는 전부 옵셔널이고 역관계가 있어야 한다
// 그래서 관계를 아예 쓰지 않고 UUID 외래키로만 잇는다. 조인은 앱에서 한다.
// 이 규칙을 어기면 앱이 던지지 않고 그냥 죽는다(NSPersistentCloudKitContainer 의 precondition).
//
// enum 도 rawValue 문자열로 저장한다. 나중에 케이스를 추가해도 기존 저장소가 깨지지 않는다.

@Model
final class MedicationRecord {

    var id: UUID = UUID()
    var name: String = ""
    var strengthText: String = ""
    var formRaw: String = Medication.Form.tablet.rawValue
    var kindRaw: String = Medication.Kind.scheduled.rawValue
    var statusRaw: String = Medication.Status.active.rawValue
    var note: String = ""
    var catalogID: String?
    var purposeLine: String = ""
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String = "",
        strengthText: String = "",
        formRaw: String = Medication.Form.tablet.rawValue,
        kindRaw: String = Medication.Kind.scheduled.rawValue,
        statusRaw: String = Medication.Status.active.rawValue,
        note: String = "",
        catalogID: String? = nil,
        purposeLine: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.strengthText = strengthText
        self.formRaw = formRaw
        self.kindRaw = kindRaw
        self.statusRaw = statusRaw
        self.note = note
        self.catalogID = catalogID
        self.purposeLine = purposeLine
        self.createdAt = createdAt
    }

    static func make(from core: Medication) -> MedicationRecord {
        MedicationRecord(
            id: core.id,
            name: core.name,
            strengthText: core.strengthText,
            formRaw: core.form.rawValue,
            kindRaw: core.kind.rawValue,
            statusRaw: core.status.rawValue,
            note: core.note,
            catalogID: core.catalogID,
            purposeLine: core.purposeLine
        )
    }

    var core: Medication {
        Medication(
            id: id,
            name: name,
            strengthText: strengthText,
            form: Medication.Form(rawValue: formRaw) ?? .tablet,
            kind: Medication.Kind(rawValue: kindRaw) ?? .scheduled,
            status: Medication.Status(rawValue: statusRaw) ?? .active,
            note: note,
            catalogID: catalogID,
            purposeLine: purposeLine
        )
    }
}

@Model
final class ScheduleRecord {

    var id: UUID = UUID()
    var medicationID: UUID = UUID()
    /// `DoseSlot.storageKey`
    var slotKey: String = DoseSlot.morning.storageKey
    var hour: Int = 8
    var minute: Int = 0
    /// Weekday.rawValue 목록.
    var weekdayValues: [Int] = Array(1...7)
    var dosePerIntake: Decimal = 1
    var startDate: Date?
    var endDate: Date?

    init(
        id: UUID = UUID(),
        medicationID: UUID = UUID(),
        slotKey: String = DoseSlot.morning.storageKey,
        hour: Int = 8,
        minute: Int = 0,
        weekdayValues: [Int] = Array(1...7),
        dosePerIntake: Decimal = 1,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.id = id
        self.medicationID = medicationID
        self.slotKey = slotKey
        self.hour = hour
        self.minute = minute
        self.weekdayValues = weekdayValues
        self.dosePerIntake = dosePerIntake
        self.startDate = startDate
        self.endDate = endDate
    }

    static func make(from core: Schedule) -> ScheduleRecord {
        ScheduleRecord(
            id: core.id,
            medicationID: core.medicationID,
            slotKey: core.slot.storageKey,
            hour: core.timeOfDay.hour,
            minute: core.timeOfDay.minute,
            weekdayValues: core.weekdays.map(\.rawValue).sorted(),
            dosePerIntake: core.dosePerIntake,
            startDate: core.startDate,
            endDate: core.endDate
        )
    }

    var core: Schedule {
        Schedule(
            id: id,
            medicationID: medicationID,
            slot: DoseSlot(storageKey: slotKey) ?? .morning,
            timeOfDay: TimeOfDay(hour: hour, minute: minute),
            weekdays: Set(weekdayValues.compactMap(Weekday.init(rawValue:))),
            dosePerIntake: dosePerIntake,
            startDate: startDate,
            endDate: endDate
        )
    }
}

@Model
final class DoseEventRecord {

    var id: UUID = UUID()
    var medicationID: UUID = UUID()
    var scheduledAt: Date = Date()
    var actualAt: Date?
    var statusRaw: String = DoseEvent.Status.unrecorded.rawValue
    var skipReason: String?
    var sourceRaw: String = DoseEvent.Source.phone.rawValue
    var quantity: Decimal = 1
    var kindRaw: String = DoseEvent.Kind.scheduled.rawValue
    var slotKey: String?

    init(
        id: UUID = UUID(),
        medicationID: UUID = UUID(),
        scheduledAt: Date = Date(),
        actualAt: Date? = nil,
        statusRaw: String = DoseEvent.Status.unrecorded.rawValue,
        skipReason: String? = nil,
        sourceRaw: String = DoseEvent.Source.phone.rawValue,
        quantity: Decimal = 1,
        kindRaw: String = DoseEvent.Kind.scheduled.rawValue,
        slotKey: String? = nil
    ) {
        self.id = id
        self.medicationID = medicationID
        self.scheduledAt = scheduledAt
        self.actualAt = actualAt
        self.statusRaw = statusRaw
        self.skipReason = skipReason
        self.sourceRaw = sourceRaw
        self.quantity = quantity
        self.kindRaw = kindRaw
        self.slotKey = slotKey
    }

    static func make(from core: DoseEvent) -> DoseEventRecord {
        DoseEventRecord(
            id: core.id,
            medicationID: core.medicationID,
            scheduledAt: core.scheduledAt,
            actualAt: core.actualAt,
            statusRaw: core.status.rawValue,
            skipReason: core.skipReason,
            sourceRaw: core.source.rawValue,
            quantity: core.quantity,
            kindRaw: core.kind.rawValue,
            slotKey: core.slotKey
        )
    }

    var core: DoseEvent {
        DoseEvent(
            id: id,
            medicationID: medicationID,
            scheduledAt: scheduledAt,
            actualAt: actualAt,
            status: DoseEvent.Status(rawValue: statusRaw) ?? .unrecorded,
            skipReason: skipReason,
            source: DoseEvent.Source(rawValue: sourceRaw) ?? .phone,
            quantity: quantity,
            kind: DoseEvent.Kind(rawValue: kindRaw) ?? .scheduled,
            slotKey: slotKey
        )
    }
}

@Model
final class StockEventRecord {

    var id: UUID = UUID()
    var medicationID: UUID = UUID()
    /// "refill" 또는 "correction".
    var kindRaw: String = "refill"
    /// refill 이면 더할 개수, correction 이면 맞춰 놓을 개수.
    var amount: Decimal = 0
    var occurredAt: Date = Date()
    var prescriptionID: UUID?
    var note: String?

    init(
        id: UUID = UUID(),
        medicationID: UUID = UUID(),
        kindRaw: String = "refill",
        amount: Decimal = 0,
        occurredAt: Date = Date(),
        prescriptionID: UUID? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.medicationID = medicationID
        self.kindRaw = kindRaw
        self.amount = amount
        self.occurredAt = occurredAt
        self.prescriptionID = prescriptionID
        self.note = note
    }

    static func make(from core: StockEvent) -> StockEventRecord {
        let kindRaw: String
        let amount: Decimal
        switch core.kind {
        case .refill(let quantity):
            kindRaw = "refill"
            amount = quantity
        case .correction(let setTo):
            kindRaw = "correction"
            amount = setTo
        }
        return StockEventRecord(
            id: core.id,
            medicationID: core.medicationID,
            kindRaw: kindRaw,
            amount: amount,
            occurredAt: core.occurredAt,
            prescriptionID: core.prescriptionID,
            note: core.note
        )
    }

    var core: StockEvent {
        StockEvent(
            id: id,
            medicationID: medicationID,
            kind: kindRaw == "correction" ? .correction(setTo: amount) : .refill(quantity: amount),
            occurredAt: occurredAt,
            prescriptionID: prescriptionID,
            note: note
        )
    }
}

@Model
final class CheckInRecord {

    var id: UUID = UUID()
    var date: Date = Date()
    var moodScore: Int = 0
    var energy: Int?
    var anxiety: Int?
    var emotionWords: [String] = []
    var sleepMinutes: Int?
    var sleepQualityRaw: String?
    var dreamed: Bool?
    var activities: [String] = []
    var note: String?
    var longText: String?
    var questionCardID: String?
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        moodScore: Int = 0,
        energy: Int? = nil,
        anxiety: Int? = nil,
        emotionWords: [String] = [],
        sleepMinutes: Int? = nil,
        sleepQualityRaw: String? = nil,
        dreamed: Bool? = nil,
        activities: [String] = [],
        note: String? = nil,
        longText: String? = nil,
        questionCardID: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.moodScore = moodScore
        self.energy = energy
        self.anxiety = anxiety
        self.emotionWords = emotionWords
        self.sleepMinutes = sleepMinutes
        self.sleepQualityRaw = sleepQualityRaw
        self.dreamed = dreamed
        self.activities = activities
        self.note = note
        self.longText = longText
        self.questionCardID = questionCardID
        self.updatedAt = updatedAt
    }

    static func make(from core: CheckIn) -> CheckInRecord {
        CheckInRecord(
            id: core.id,
            date: core.date,
            moodScore: core.mood.score,
            energy: core.energy,
            anxiety: core.anxiety,
            emotionWords: core.emotionWords,
            sleepMinutes: core.sleepMinutes,
            sleepQualityRaw: core.sleepQuality?.rawValue,
            dreamed: core.dreamed,
            activities: core.activities,
            note: core.note,
            longText: core.longText,
            questionCardID: core.questionCardID,
            updatedAt: core.updatedAt
        )
    }

    var core: CheckIn {
        CheckIn(
            id: id,
            date: date,
            mood: CheckIn.Mood(moodScore),
            energy: energy,
            anxiety: anxiety,
            emotionWords: emotionWords,
            sleepMinutes: sleepMinutes,
            sleepQuality: sleepQualityRaw.flatMap(CheckIn.SleepQuality.init(rawValue:)),
            dreamed: dreamed,
            activities: activities,
            note: note,
            longText: longText,
            questionCardID: questionCardID,
            updatedAt: updatedAt
        )
    }
}

@Model
final class SymptomEntryRecord {

    var id: UUID = UUID()
    var symptomID: String = ""
    var severity: Int = 0
    var startedAt: Date = Date()
    var durationMinutes: Int?
    var contextTags: [String] = []
    var relatedMedicationID: UUID?
    var note: String?
    var sourceRaw: String = SymptomEntry.Source.phone.rawValue

    init(
        id: UUID = UUID(),
        symptomID: String = "",
        severity: Int = 0,
        startedAt: Date = Date(),
        durationMinutes: Int? = nil,
        contextTags: [String] = [],
        relatedMedicationID: UUID? = nil,
        note: String? = nil,
        sourceRaw: String = SymptomEntry.Source.phone.rawValue
    ) {
        self.id = id
        self.symptomID = symptomID
        self.severity = severity
        self.startedAt = startedAt
        self.durationMinutes = durationMinutes
        self.contextTags = contextTags
        self.relatedMedicationID = relatedMedicationID
        self.note = note
        self.sourceRaw = sourceRaw
    }

    static func make(from core: SymptomEntry) -> SymptomEntryRecord {
        SymptomEntryRecord(
            id: core.id,
            symptomID: core.symptomID,
            severity: core.severity,
            startedAt: core.startedAt,
            durationMinutes: core.durationMinutes,
            contextTags: core.contextTags,
            relatedMedicationID: core.relatedMedicationID,
            note: core.note,
            sourceRaw: core.source.rawValue
        )
    }

    var core: SymptomEntry {
        SymptomEntry(
            id: id,
            symptomID: symptomID,
            severity: severity,
            startedAt: startedAt,
            durationMinutes: durationMinutes,
            contextTags: contextTags,
            relatedMedicationID: relatedMedicationID,
            note: note,
            source: SymptomEntry.Source(rawValue: sourceRaw) ?? .phone
        )
    }
}

@Model
final class PrescriptionRecord {

    var id: UUID = UUID()
    var visitDate: Date = Date()
    var daysSupplied: Int = 0
    var nextVisitDate: Date?
    var clinicNote: String = ""
    /// UUID.uuidString 목록. 관계를 쓰지 않는 규칙 그대로 문자열로 담는다.
    var medicationIDValues: [String] = []

    init(
        id: UUID = UUID(),
        visitDate: Date = Date(),
        daysSupplied: Int = 0,
        nextVisitDate: Date? = nil,
        clinicNote: String = "",
        medicationIDValues: [String] = []
    ) {
        self.id = id
        self.visitDate = visitDate
        self.daysSupplied = daysSupplied
        self.nextVisitDate = nextVisitDate
        self.clinicNote = clinicNote
        self.medicationIDValues = medicationIDValues
    }

    static func make(from core: Prescription) -> PrescriptionRecord {
        PrescriptionRecord(
            id: core.id,
            visitDate: core.visitDate,
            daysSupplied: core.daysSupplied,
            nextVisitDate: core.nextVisitDate,
            clinicNote: core.clinicNote,
            medicationIDValues: core.medicationIDs.map(\.uuidString)
        )
    }

    var core: Prescription {
        Prescription(
            id: id,
            visitDate: visitDate,
            daysSupplied: daysSupplied,
            nextVisitDate: nextVisitDate,
            clinicNote: clinicNote,
            medicationIDs: medicationIDValues.compactMap(UUID.init(uuidString:))
        )
    }
}

/// 스키마 한 곳. ModelContainer 와 테스트가 같은 목록을 쓴다.
enum JanjanSchema {
    static let allModels: [any PersistentModel.Type] = [
        MedicationRecord.self,
        ScheduleRecord.self,
        DoseEventRecord.self,
        StockEventRecord.self,
        CheckInRecord.self,
        SymptomEntryRecord.self,
        PrescriptionRecord.self
    ]
}
