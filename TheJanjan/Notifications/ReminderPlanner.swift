import Foundation
import SwiftData
import JanjanCore

/// 저장소의 스케줄을 알림으로 옮기는 얇은 다리.
///
/// 무엇을 언제 알릴지는 `DayPlan.weeklyReminders` 가 정하고(순수 함수·테스트 있음),
/// 여기서는 그 결과를 `NotificationManager` 가 아는 모양으로 바꿔 넘기기만 한다.
@MainActor
enum ReminderPlanner {

    /// 알림을 통째로 다시 깐다. 약이나 스케줄이 바뀔 때마다 부른다.
    ///
    /// 통째로 다시 까는 이유: 무엇이 지워졌는지 따라다니며 하나씩 취소하려면
    /// 앱과 알림센터 두 곳에 같은 목록을 유지해야 하고, 그 둘은 반드시 어긋난다.
    static func reschedule(using context: ModelContext) async {
        let medications = (try? context.fetch(FetchDescriptor<MedicationRecord>()))?.map(\.core) ?? []
        let schedules = (try? context.fetch(FetchDescriptor<ScheduleRecord>()))?.map(\.core) ?? []

        let reminders = DayPlan.weeklyReminders(schedules: schedules, medications: medications)

        await NotificationManager.shared.rescheduleDoseReminders(
            reminders.map { reminder in
                NotificationManager.SlotReminder(
                    slot: reminder.slot,
                    time: reminder.time,
                    weekdays: [reminder.weekday],
                    medicationIDs: reminder.medicationIDs,
                    medicationNames: reminder.medicationNames
                )
            }
        )
    }
}
