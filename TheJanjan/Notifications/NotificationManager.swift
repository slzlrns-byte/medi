import Foundation
import OSLog
import UserNotifications
import JanjanCore

/// 복약 알림의 식별자와 페이로드.
///
/// NotificationManager 안에 두지 않는 이유: 알림 델리게이트는 MainActor 밖에서 불리므로
/// 이 값들은 어떤 액터에도 묶여 있으면 안 된다.
enum DoseNotification {

    static let categoryID = "DOSE_REMINDER"

    static let actionTaken = "DOSE_TAKEN"
    static let actionSkipped = "DOSE_SKIPPED"
    static let actionSnooze = "DOSE_SNOOZE"

    static let slotKeyField = "slotKey"
    static let medicationIDsField = "medicationIDs"

    /// 재알림은 30분 뒤 딱 한 번. 그 뒤로는 홈 화면에 조용히 남긴다.
    static let snoozeInterval: TimeInterval = 30 * 60

    /// 알림 응답에서 필요한 것만 뽑아 낸 값. 액터 경계를 건너야 해서 Sendable 이다.
    struct ActionPayload: Sendable {
        let actionIdentifier: String
        let slotKey: String
        let medicationIDs: [UUID]

        init?(response: UNNotificationResponse) {
            let userInfo = response.notification.request.content.userInfo
            guard let slotKey = userInfo[DoseNotification.slotKeyField] as? String else { return nil }
            let rawIDs = userInfo[DoseNotification.medicationIDsField] as? [String] ?? []
            self.actionIdentifier = response.actionIdentifier
            self.slotKey = slotKey
            self.medicationIDs = rawIDs.compactMap(UUID.init(uuidString:))
        }
    }

    static func doseAction(for identifier: String) -> WatchMessage.DoseAction? {
        switch identifier {
        case actionTaken: return .taken
        case actionSkipped: return .skipped
        case actionSnooze: return .snooze
        default: return nil
        }
    }
}

/// 복약 알림 (설계 11절 — 알림은 적을수록 신뢰받는다).
///
/// 시간대마다 1개만 보낸다. 약별로 쪼개지 않는다.
/// 액션(복용함·건너뜀·30분 뒤)은 앱을 열지 않고 백그라운드에서 처리된다.
@MainActor
final class NotificationManager: NSObject {

    static let shared = NotificationManager()

    private let logger = Logger(subsystem: Janjan.appBundleID, category: "notifications")
    private let center = UNUserNotificationCenter.current()

    /// 실제 저장을 담당하는 쪽. 소유자는 AppServices 이고 여기서는 빌려 쓴다.
    weak var doseLogger: (any DoseLogging)?

    /// 잠금화면 미리보기에 약 이름을 띄울지. 기본은 표시, 설정에서 끌 수 있다.
    /// 설정의 "잠금화면에서 약 이름 숨기기" 를 뒤집은 값.
    ///
    /// 저장은 UserDefaults 한 곳에서 한다. 화면이 `@AppStorage` 로만 들고 있으면
    /// 알림을 굽는 이 클래스는 그 값을 영영 못 보고, 토글은 아무 일도 하지 않는
    /// 장식이 된다. 정신과 약 이름이 잠금화면에 뜨는 문제라 그냥 두면 안 된다.
    static let hideNamesDefaultsKey = "janjan.notifications.hideMedicationNames"

    var showsMedicationNames: Bool {
        !UserDefaults.standard.bool(forKey: Self.hideNamesDefaultsKey)
    }

    private override init() {
        super.init()
    }

    // MARK: - 준비

    /// 앱이 뜰 때 한 번. 권한을 조르지 않고 카테고리 등록과 델리게이트 연결만 한다.
    func bootstrap() {
        center.delegate = self
        registerCategories()
    }

    /// 온보딩 2번째 화면에서 "왜 필요한지" 한 문장을 보여 준 뒤에만 부른다.
    /// 거부해도 앱은 완전히 동작한다(심사 2.1 완결성).
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            logger.error("알림 권한 요청 실패: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func registerCategories() {
        let taken = UNNotificationAction(identifier: DoseNotification.actionTaken, title: "복용함", options: [])
        let skipped = UNNotificationAction(identifier: DoseNotification.actionSkipped, title: "건너뜀", options: [])
        let snooze = UNNotificationAction(identifier: DoseNotification.actionSnooze, title: "30분 뒤", options: [])

        let category = UNNotificationCategory(
            identifier: DoseNotification.categoryID,
            actions: [taken, skipped, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    // MARK: - 예약

    /// 한 시간대에 예정된 약을 묶은 알림 한 건.
    struct SlotReminder {
        let slot: DoseSlot
        let time: TimeOfDay
        let weekdays: Set<Weekday>
        let medicationIDs: [UUID]
        let medicationNames: [String]

        init(
            slot: DoseSlot,
            time: TimeOfDay? = nil,
            weekdays: Set<Weekday> = Weekday.everyday,
            medicationIDs: [UUID],
            medicationNames: [String]
        ) {
            self.slot = slot
            self.time = time ?? slot.defaultTime
            self.weekdays = weekdays
            self.medicationIDs = medicationIDs
            self.medicationNames = medicationNames
        }
    }

    /// 시간대별 알림을 통째로 다시 깐다. 스케줄이 바뀌면 이 함수만 다시 부르면 된다.
    func rescheduleDoseReminders(_ reminders: [SlotReminder]) async {
        let pending = await center.pendingNotificationRequests()
        let ourIDs = pending.map(\.identifier).filter { $0.hasPrefix("dose-") }
        center.removePendingNotificationRequests(withIdentifiers: ourIDs)

        for reminder in reminders where !reminder.medicationIDs.isEmpty {
            for weekday in reminder.weekdays.sorted() {
                let request = makeRequest(for: reminder, weekday: weekday)
                do {
                    try await center.add(request)
                } catch {
                    logger.error("알림 예약 실패: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func makeRequest(for reminder: SlotReminder, weekday: Weekday) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "\(reminder.slot.labelKo) 약"
        content.body = bodyText(for: reminder)
        content.sound = .default
        content.categoryIdentifier = DoseNotification.categoryID
        content.userInfo = [
            DoseNotification.slotKeyField: reminder.slot.storageKey,
            DoseNotification.medicationIDsField: reminder.medicationIDs.map(\.uuidString)
        ]

        var components = DateComponents()
        components.hour = reminder.time.hour
        components.minute = reminder.time.minute
        components.weekday = weekday.rawValue

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        return UNNotificationRequest(
            identifier: "dose-\(reminder.slot.storageKey)-\(weekday.rawValue)",
            content: content,
            trigger: trigger
        )
    }

    /// "쿠에티아핀 · 라모트리진" 또는 이름을 숨겼을 때 "2종".
    private func bodyText(for reminder: SlotReminder) -> String {
        guard showsMedicationNames, !reminder.medicationNames.isEmpty else {
            return "\(reminder.medicationIDs.count)종"
        }
        return reminder.medicationNames.joined(separator: " · ")
    }

    /// 30분 뒤 재알림. 한 번만 걸고 그 뒤로는 홈에 조용히 남긴다.
    func snooze(slotKey: String, medicationIDs: [UUID]) {
        let slot = DoseSlot(storageKey: slotKey)
        let content = UNMutableNotificationContent()
        content.title = "\(slot?.labelKo ?? "복용") 약"
        content.body = "아직 남아 있어요."
        content.sound = .default
        content.categoryIdentifier = DoseNotification.categoryID
        content.userInfo = [
            DoseNotification.slotKeyField: slotKey,
            DoseNotification.medicationIDsField: medicationIDs.map(\.uuidString)
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: DoseNotification.snoozeInterval,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "dose-snooze-\(slotKey)",
            content: content,
            trigger: trigger
        )
        let logger = self.logger
        center.add(request) { error in
            if let error {
                logger.error("재알림 예약 실패: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 이미 배달돼 잠금화면·알림센터에 떠 있는 이 약의 알림을 걷는다.
    ///
    /// 예약된 알림(`pending`)만 지우면 이미 나가 있는 알림은 그대로 남는다.
    /// 지운 약의 이름이 계속 보이는 것도 문제고, 거기서 "복용함" 을 누르면
    /// 주인 없는 기록이 새로 생기는 것은 더 문제다.
    func removeDeliveredNotifications(for medicationID: UUID) {
        let idText = medicationID.uuidString
        center.getDeliveredNotifications { [center] delivered in
            let ids = delivered.compactMap { notification -> String? in
                let info = notification.request.content.userInfo
                guard let raw = info[DoseNotification.medicationIDsField] as? [String],
                      raw.contains(idText)
                else { return nil }
                return notification.request.identifier
            }
            guard !ids.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    func cancelAllDoseReminders() {
        center.removeAllPendingNotificationRequests()
        // 이미 나가 있는 알림도 함께 걷는다. 전체 삭제를 누른 뒤에도
        // 잠금화면에 약 이름이 남아 있으면 지운 의미가 없다.
        center.removeAllDeliveredNotifications()
    }

    // MARK: - 액션 처리

    func handle(_ payload: DoseNotification.ActionPayload, at date: Date = Date()) {
        // 알림 본체를 탭한 경우(액션 아님)에는 앱만 열고 아무것도 기록하지 않는다.
        guard let action = DoseNotification.doseAction(for: payload.actionIdentifier) else { return }

        guard let doseLogger else {
            logger.warning("DoseLogger 가 연결되지 않아 알림 액션을 흘려보냈습니다.")
            return
        }
        doseLogger.logDose(
            medicationIDs: payload.medicationIDs,
            slotKey: payload.slotKey,
            action: action,
            source: .notificationAction,
            at: date
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let payload = DoseNotification.ActionPayload(response: response)
        Task { @MainActor in
            if let payload {
                NotificationManager.shared.handle(payload)
            }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 앱을 보고 있는 중에도 배너는 띄우되 소리는 내지 않는다.
        completionHandler([.banner, .list])
    }
}
