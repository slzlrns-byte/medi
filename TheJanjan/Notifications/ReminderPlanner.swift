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

        await rescheduleAppointments(using: context)
    }

    /// 진료 알림도 같은 자리에서 다시 깐다. 처방을 저장하거나 설정을 바꾸면
    /// 이 함수를 부르는 쪽이 하나여야 둘이 어긋나지 않는다.
    static func rescheduleAppointments(using context: ModelContext) async {
        let leadDays = UserDefaults.standard.object(forKey: appointmentLeadDaysKey) as? Int
            ?? AppointmentReminder.defaultLeadDays

        let visits = (try? context.fetch(FetchDescriptor<PrescriptionRecord>()))?
            .compactMap { $0.nextVisitDate } ?? []

        await NotificationManager.shared.rescheduleAppointmentReminders(
            AppointmentReminder.reminders(
                visitDates: visits,
                leadDays: leadDays,
                now: Date()
            )
        )
    }

    /// 설정과 여기가 같은 키를 봐야 한다. 한쪽만 고치면 토글이 아무 일도 하지 않는다.
    static let appointmentLeadDaysKey = "appointmentLeadDays"
}
