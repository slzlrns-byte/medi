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
    /// 한 시간대에 약이 둘 이상일 때 쓰는 카테고리. 처리는 똑같고 버튼 문구만
    /// 다르다 - "복용함" 한 번이 그 시간대의 약 **전부**에 걸린다는 것을
    /// 버튼이 직접 말해야 잠금화면과 워치에서 믿고 누를 수 있다(2026-09-19).
    static let categoryAllID = "DOSE_REMINDER_ALL"

    /// 약이 하나뿐인 시간대에 "전부" 라고 말하면 그것대로 어색하다. 개수로 고른다.
    static func category(forMedicationCount count: Int) -> String {
        count > 1 ? categoryAllID : categoryID
    }

    static let actionTaken = "DOSE_TAKEN"
    static let actionSkipped = "DOSE_SKIPPED"
    static let actionSnooze = "DOSE_SNOOZE"

    static let slotKeyField = "slotKey"
    static let medicationIDsField = "medicationIDs"

    /// 재알림은 30분 뒤 딱 한 번. 그 뒤로는 홈 화면에 조용히 남긴다.
    static let snoozeInterval: TimeInterval = 30 * 60

    // 똑똑한 재알림(Pro) - 답이 없으면 몇 분 간격으로 몇 번 더 물을지.
    // 설정과 예약이 같은 키를 봐야 해서 여기 둔다. 분이 0 이면 꺼진 것이다.
    static let followUpMinutesKey = "janjan.notifications.followUpMinutes"
    static let followUpCountKey = "janjan.notifications.followUpCount"
    static let followUpMinuteChoices = [10, 20, 30]
    static let followUpCountChoices = [1, 2, 3]
    static let followUpIDPrefix = "dosefu-"

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

    /// 카테고리는 둘이다. 액션 식별자가 같으므로 응답을 받는 쪽은 구분할 필요가 없다.
    func registerCategories() {
        let snooze = UNNotificationAction(
            identifier: DoseNotification.actionSnooze,
            title: t("30분 뒤", "In 30 min"),
            options: []
        )

        func category(_ identifier: String, taken: String, skipped: String) -> UNNotificationCategory {
            UNNotificationCategory(
                identifier: identifier,
                actions: [
                    UNNotificationAction(identifier: DoseNotification.actionTaken, title: taken, options: []),
                    UNNotificationAction(identifier: DoseNotification.actionSkipped, title: skipped, options: []),
                    snooze
                ],
                intentIdentifiers: [],
                options: []
            )
        }

        center.setNotificationCategories([
            category(
                DoseNotification.categoryID,
                taken: t("복용함", "Taken"),
                skipped: t("건너뜀", "Skip")
            ),
            category(
                DoseNotification.categoryAllID,
                taken: t("전부 복용함", "All taken"),
                skipped: t("전부 건너뜀", "Skip all")
            )
        ])
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
    ///
    /// 예약된 스누즈("dose-snooze-")는 건드리지 않는다 - "30분 뒤" 를 눌러 둔
    /// 사람이 그 사이 앱을 열면 약속한 재알림이 사라졌다(QA 2026-09-19).
    func rescheduleDoseReminders(_ reminders: [SlotReminder]) async {
        let pending = await center.pendingNotificationRequests()
        let ourIDs = pending.map(\.identifier).filter {
            $0.hasPrefix("dose-") && !$0.hasPrefix("dose-snooze-")
        }
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
        content.title = titleText(for: reminder.slot)
        content.body = bodyText(for: reminder)
        content.sound = .default
        content.categoryIdentifier = DoseNotification.category(forMedicationCount: reminder.medicationIDs.count)
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

    /// 오늘 남은 시간대의 되물음(Pro 똑똑한 재알림)을 다시 깐다.
    ///
    /// 하루치만 미리 건다 - iOS 의 예약 한도(64) 안에 머물고, 날이 바뀌면
    /// 앱이 열리거나 기록이 남을 때 다시 깐다. 시간대에 답이 남으면
    /// `clearFollowUps` 가 그 시간대 것을 걷고, 이미 답한 시간대는
    /// 처음부터 걸지 않는다.
    func rescheduleTodayFollowUps(
        _ reminders: [SlotReminder],
        isPro: Bool,
        answeredSlotKeys: Set<String> = [],
        now: Date = Date()
    ) async {
        let pending = await center.pendingNotificationRequests()
        let ourIDs = pending.map(\.identifier).filter { $0.hasPrefix(DoseNotification.followUpIDPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ourIDs)

        let defaults = UserDefaults.standard
        let minutes = defaults.integer(forKey: DoseNotification.followUpMinutesKey)
        let storedCount = defaults.object(forKey: DoseNotification.followUpCountKey) as? Int ?? 2
        let count = max(1, min(storedCount, 3))
        guard isPro, minutes > 0 else { return }

        // 예약 한도(64) 방어. 넘치면 iOS 가 아무거나 조용히 버리는데,
        // 그 "아무거나" 가 기본 복약 알림이면 최악이다. 되물음은 남는
        // 자리에만 채우고, 자리가 없으면 이른 시간대부터 채운다.
        var budget = max(0, 60 - (pending.count - ourIDs.count))

        let calendar = Calendar.current
        guard let today = Weekday(rawValue: calendar.component(.weekday, from: now)) else { return }

        let todayReminders = reminders
            .filter {
                $0.weekdays.contains(today)
                    && !$0.medicationIDs.isEmpty
                    && !answeredSlotKeys.contains($0.slot.storageKey)
            }
            .sorted { ($0.time.hour, $0.time.minute) < ($1.time.hour, $1.time.minute) }

        for reminder in todayReminders {
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = reminder.time.hour
            components.minute = reminder.time.minute
            guard let slotDate = calendar.date(from: components) else { continue }

            for n in 1...count {
                guard budget > 0 else { return }
                let fireAt = slotDate.addingTimeInterval(TimeInterval(minutes * 60 * n))
                guard fireAt > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = titleText(for: reminder.slot)
                content.body = t("아직 기록이 없어요.", "Still not logged.")
                content.sound = .default
                content.categoryIdentifier = DoseNotification.category(forMedicationCount: reminder.medicationIDs.count)
                content.userInfo = [
                    DoseNotification.slotKeyField: reminder.slot.storageKey,
                    DoseNotification.medicationIDsField: reminder.medicationIDs.map(\.uuidString)
                ]

                let fireComponents = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: fireAt
                )
                let request = UNNotificationRequest(
                    identifier: "\(DoseNotification.followUpIDPrefix)\(reminder.slot.storageKey)-\(n)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: fireComponents, repeats: false)
                )
                do {
                    try await center.add(request)
                    budget -= 1
                } catch {
                    logger.error("되물음 예약 실패: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// 이 시간대에 답이 남았다 - 걸려 있던 되물음과 이미 떠 있는 되물음을 걷는다.
    func clearFollowUps(slotKey: String) {
        let ids = (1...3).map { "\(DoseNotification.followUpIDPrefix)\(slotKey)-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// "아침 약" / "Morning meds". " 약" 을 그대로 붙이면 영어에서 어색해
    /// 두 언어를 따로 짓는다.
    private func titleText(for slot: DoseSlot) -> String {
        JanjanLanguage.current == .english ? "\(slot.labelEn) meds" : "\(slot.labelKo) 약"
    }

    /// "쿠에티아핀 · 라모트리진" 또는 이름을 숨겼을 때 "2종"/"2 meds".
    ///
    /// `JanjanPrivacy.hidesNames`(Pro "약 이름 가리기")도 함께 본다 — 앱 안에서
    /// 가린 이름이 잠금화면 알림으로 새면 그 기능이 뚫린 것과 같다.
    private func bodyText(for reminder: SlotReminder) -> String {
        guard showsMedicationNames, !JanjanPrivacy.hidesNames, !reminder.medicationNames.isEmpty else {
            let count = reminder.medicationIDs.count
            return t("\(count)종", count == 1 ? "1 med" : "\(count) meds")
        }
        return reminder.medicationNames.joined(separator: " · ")
    }

    // MARK: - 진료 알림

    /// 진료 알림을 통째로 다시 깐다.
    ///
    /// 복약 알림과 식별자 앞머리가 다르므로(`visit-` / `dose-`) 서로를 지우지 않는다.
    /// 반복하지 않는 한 번짜리라, 지난 것은 iOS 가 알아서 치운다.
    func rescheduleAppointmentReminders(_ reminders: [AppointmentReminder.Reminder]) async {
        let pending = await center.pendingNotificationRequests()
        let ourIDs = pending.map(\.identifier).filter { $0.hasPrefix("visit-") }
        center.removePendingNotificationRequests(withIdentifiers: ourIDs)

        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.titleKo
            content.body = reminder.bodyKo
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: reminder.fireAt
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            do {
                try await center.add(
                    UNNotificationRequest(
                        identifier: reminder.id,
                        content: content,
                        trigger: trigger
                    )
                )
            } catch {
                logger.error("진료 알림 예약 실패: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 30분 뒤 재알림. 한 번만 걸고 그 뒤로는 홈에 조용히 남긴다.
    func snooze(slotKey: String, medicationIDs: [UUID]) {
        // "30분 뒤" 를 눌렀으면 그 스누즈가 이 시간대의 재알림이다 - 남아 있던
        // 되물음(Pro)까지 그대로 두면 비슷한 시각에 같은 것을 두 번 묻는다.
        clearFollowUps(slotKey: slotKey)
        let slot = DoseSlot(storageKey: slotKey)
        let content = UNMutableNotificationContent()
        if let slot {
            content.title = titleText(for: slot)
        } else {
            content.title = t("복용 약", "Meds")
        }
        content.body = t("아직 남아 있어요.", "Still waiting for you.")
        content.sound = .default
        content.categoryIdentifier = DoseNotification.category(forMedicationCount: medicationIDs.count)
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

    /// 복약·진료 알림을 모두 걷는다. "모든 데이터 삭제" 가 부른다 —
    /// 지우고 나서도 사라진 약의 알림이 뜨면 안 된다.
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
