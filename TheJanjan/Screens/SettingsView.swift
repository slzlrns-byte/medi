import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import JanjanCore

/// 설정 — 오늘 탭 우상단 톱니에서 올라온다 (설계 03절).
struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var lock: AppLockManager

    /// 번호를 정하는 화면을 띄울 이유. nil 이면 닫혀 있다.
    @State private var setupMode: PasscodeSetupView.Mode?

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isAskingNotification = false
    @EnvironmentObject private var pro: ProStore

    @AppStorage(NotificationManager.hideNamesDefaultsKey) private var hidesMedicationNames = false
    @AppStorage(ReminderPlanner.appointmentLeadDaysKey)
    private var appointmentLeadDays = AppointmentReminder.defaultLeadDays

    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingPaywall = false
    @State private var isShowingLicenses = false

    @AppStorage(JanjanFontChoice.defaultsKey) private var fontChoiceRaw = JanjanFontChoice.standard.rawValue
    @AppStorage(JanjanTheme.defaultsKey) private var themeRaw = JanjanTheme.standard.rawValue
    @AppStorage(JanjanLanguage.defaultsKey) private var languageRaw = JanjanLanguage.standard.rawValue

    var body: some View {
        NavigationStack {
            Form {
                proSection
                fontSection
                notificationsSection
                securitySection
                privacySection
                safetySection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.fog.ignoresSafeArea())
            .task { await refreshNotificationStatus() }
            .navigationTitle(t("설정", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView()
            }
            .confirmationDialog(
                t("모든 데이터를 삭제할까요?", "Delete everything?"),
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(t("삭제", "Delete"), role: .destructive) { deleteEverything() }
                Button(t("취소", "Cancel"), role: .cancel) {}
            } message: {
                Text(deleteWarningKo)
            }
            .sheet(isPresented: $isShowingLicenses) {
                LicenseNoticeView()
            }
            .fullScreenCover(isPresented: $isAskingNotification) {
                NotificationPermissionView {
                    NotificationPermissionGate.hasAsked = true
                    Task {
                        await refreshNotificationStatus()
                        await ReminderPlanner.reschedule(using: context)
                    }
                }
            }
            .sheet(item: $setupMode) { mode in
                PasscodeSetupView(mode: mode) { setupMode = nil }
                    .environmentObject(lock)
            }
        }
    }

    // MARK: - Pro

    /// 심사자가 복원 버튼을 찾는 곳이기도 하다(심사 노트에 "복원은 설정 > Pro" 라고 적었다).
    private var proSection: some View {
        Section {
            LabeledContent(t("상태", "Status")) {
                Text(pro.isPro ? t("Pro 사용 중", "Using Pro") : t("무료", "Free"))
                    .foregroundStyle(Color.muted)
            }

            Button(t("Pro 알아보기", "Learn about Pro")) {
                isShowingPaywall = true
            }
            .foregroundStyle(Color.ink)

            Button(t("구매 복원", "Restore purchase")) {
                Task { await pro.restore() }
            }
            .foregroundStyle(Color.ink)
            .disabled(pro.isLoading)

            if pro.isPro, let url = URL(string: ProProduct.manageSubscriptionsURLString) {
                Link(t("구독 관리", "Manage subscription"), destination: url)
                    .foregroundStyle(Color.ink)
            }
        } header: {
            Text("Pro")
        } footer: {
            Text(proFooterKo)
        }
    }

    private var proFooterKo: String {
        if let message = pro.lastError { return message }
        if pro.isPro {
            return t(
                "기간과 해지는 \"구독 관리\" 에서 확인할 수 있어요.",
                "You can check the period and cancel it under \"Manage subscription.\""
            )
        }
        return t("무료 기능은 구독 없이 계속 쓸 수 있어요.", "Free features keep working without a subscription.")
    }

    // MARK: - 알림

    private var fontSection: some View {
        Section {
            Picker(t("언어", "Language"), selection: $languageRaw) {
                ForEach(JanjanLanguage.allCases, id: \.rawValue) { language in
                    Text(language.labelNative).tag(language.rawValue)
                }
            }
            .onChange(of: languageRaw) { _, newValue in
                // 위젯도 같은 언어를 읽도록 앱 그룹에 함께 쓰고, 워치 화면도 새로 밀어 준다.
                let language = JanjanLanguage(rawValue: newValue) ?? .standard
                JanjanLanguage.store(language)
                AppServices.shared.pushWatchSnapshot()
            }
            Picker(t("테마", "Theme"), selection: $themeRaw) {
                ForEach(JanjanTheme.allCases, id: \.rawValue) { theme in
                    Text(theme.label(JanjanLanguage.current)).tag(theme.rawValue)
                }
            }
            .onChange(of: themeRaw) { _, _ in
                // 워치의 기분 원도 같은 색을 쓰게 새 스냅샷을 민다.
                AppServices.shared.pushWatchSnapshot()
            }
            Picker(t("서체", "Typeface"), selection: $fontChoiceRaw) {
                ForEach(JanjanFontChoice.allCases, id: \.rawValue) { choice in
                    Text(choice.label(JanjanLanguage.current)).tag(choice.rawValue)
                }
            }
        } header: {
            Text(t("화면", "Appearance"))
        } footer: {
            Text(footerForScreenSection)
        }
    }

    private var footerForScreenSection: String {
        let theme = JanjanTheme(rawValue: themeRaw) ?? .standard
        let font = JanjanFontChoice(rawValue: fontChoiceRaw)?.detail(JanjanLanguage.current) ?? ""
        return "\(theme.detail(JanjanLanguage.current))\n\(font)"
    }

    private var notificationsSection: some View {
        Section {
            // 권한이 없으면 알림은 한 건도 뜨지 않는다. 그 사실과 켜는 길이
            // 여기 없으면 사용자는 왜 안 오는지 영영 알 수 없다.
            switch notificationStatus {
            case .notDetermined:
                Button(t("알림 켜기", "Turn on notifications")) { isAskingNotification = true }
                    .foregroundStyle(Color.ink)
            case .denied:
                Button(t("iOS 설정에서 알림 켜기", "Turn on notifications in iOS Settings")) { openSystemSettings() }
                    .foregroundStyle(Color.ink)
            default:
                LabeledContent(t("복용 알림", "Dose reminders")) {
                    Text(t("켜져 있어요", "On"))
                        .foregroundStyle(Color.muted)
                }
            }

            Toggle(t("잠금화면에서 약 이름 숨기기", "Hide medication names on lock screen"), isOn: $hidesMedicationNames)
                .onChange(of: hidesMedicationNames) { _, _ in
                    // 이미 예약된 알림은 문구가 구워진 채로 남아 있다. 다시 깔아야 바뀐다.
                    Task { await ReminderPlanner.reschedule(using: context) }
                }

            Picker(t("진료 알림", "Appointment reminders"), selection: $appointmentLeadDays) {
                ForEach(AppointmentReminder.allowedLeadDays, id: \.self) { days in
                    Text(AppointmentReminder.leadLabel(forDays: days, language: JanjanLanguage.current)).tag(days)
                }
            }
            .onChange(of: appointmentLeadDays) { _, _ in
                Task { await ReminderPlanner.rescheduleAppointments(using: context) }
            }
        } header: {
            Text(t("알림", "Notifications"))
        } footer: {
            Text(notificationFooterKo)
        }
    }

    private var notificationFooterKo: String {
        switch notificationStatus {
        case .denied:
            return t(
                "iOS 설정에서 알림을 꺼 두셔서 복용 알림이 오지 않습니다. 기록은 앱에서 직접 남길 수 있어요.",
                "Notifications are off in iOS Settings, so dose reminders won't arrive. You can still log doses directly in the app."
            )
        case .notDetermined:
            return t(
                "켜면 약 시간에 알려드리고, 알림에서 바로 복용함·건너뜀을 누를 수 있어요.",
                "Turning this on notifies you at dose time, and you can tap Taken or Skipped right from the notification."
            )
        default:
            return t(
                "이름 숨기기를 켜면 알림에 \"취침 약 2종\" 처럼 개수만 보입니다. 진료 알림은 처방에 다음 진료일을 적어 두면 갑니다.",
                "Turning on name hiding shows only a count in the notification, like \"2 bedtime medications.\" Appointment reminders go out once a prescription has a next visit date."
            )
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await NotificationManager.shared.authorizationStatus()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    // MARK: - 보안

    private var securitySection: some View {
        Section {
            Toggle(t("앱 잠금 (네 자리 번호)", "App lock (4-digit code)"), isOn: appLockBinding)

            if lock.isEnabled {
                Button(t("번호 바꾸기", "Change code")) { setupMode = .change }
                    .foregroundStyle(Color.ink)

                Toggle(t("생체인식으로도 열기", "Also unlock with biometrics"), isOn: biometricsBinding)

                Picker(t("다시 잠그기", "Lock again"), selection: graceSecondsBinding) {
                    ForEach(LockPolicy.allowedGraceSeconds, id: \.self) { seconds in
                        // LockPolicy 는 코어에 한국어 라벨만 있다(그래프 라벨에 언어 인자가 없음).
                        Text(LockPolicy.graceLabelKo(forSeconds: seconds)).tag(seconds)
                    }
                }
            }
        } header: {
            Text(t("보안", "Security"))
        } footer: {
            Text(securityFooterKo)
        }
    }

    /// 켤 때는 번호를 정하는 화면을 띄우고, 그 화면이 성공해야 켜진다.
    /// 끌 때는 지금 열려 있는 사람이 누르는 것이므로 곧바로 끈다.
    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { lock.isEnabled },
            set: { wanted in
                if wanted {
                    setupMode = .create
                } else {
                    lock.disable()
                }
            }
        )
    }

    private var biometricsBinding: Binding<Bool> {
        Binding(
            get: { lock.usesBiometrics },
            set: { lock.usesBiometrics = $0 }
        )
    }

    private var graceSecondsBinding: Binding<Int> {
        Binding(
            get: { lock.graceSeconds },
            set: { lock.graceSeconds = $0 }
        )
    }

    private var securityFooterKo: String {
        // AppLockManager 는 코어가 아니라 이 팀 소유가 아닌 로직 파일이라
        // failureMessageKo 는 언어를 따라가지 못하고 한국어로 남는다.
        if let message = lock.failureMessageKo { return message }
        if lock.isEnabled {
            guard lock.canRecoverWithDevice else {
                return t(
                    "앱을 열 때 네 자리 번호를 누릅니다. 이 기기에는 기기 암호가 없어서, 번호를 잊으면 기록을 열 방법이 없습니다.",
                    "You enter your 4-digit code to open the app. This device has no passcode set, so if you forget your code, there is no way to open your records."
                )
            }
            return t(
                "앱을 열 때 네 자리 번호를 누릅니다. 번호를 잊으면 Face ID · Touch ID 또는 기기 암호로 되찾을 수 있습니다.",
                "You enter your 4-digit code to open the app. If you forget it, you can recover with Face ID, Touch ID, or your device passcode."
            )
        }
        return t(
            "켜면 앱을 열 때 네 자리 번호를 누릅니다. 번호는 이 기기에만 저장되고 다른 기기로 따라가지 않습니다.",
            "Turning this on requires a 4-digit code to open the app. The code is stored only on this device and does not carry over to others."
        )
    }

    // MARK: - 개인정보

    private var privacySection: some View {
        Section {
            LabeledContent(t("저장 위치", "Storage")) {
                // JanjanModelContainer 는 이 팀 소유 파일이 아니라 labelKo 만 있다.
                Text(JanjanModelContainer.activeStorage.labelKo)
                    .foregroundStyle(Color.muted)
            }

            Button(role: .destructive) {
                isShowingDeleteConfirmation = true
            } label: {
                Text(t("모든 데이터 삭제", "Delete everything"))
            }
        } header: {
            Text(t("개인정보", "Privacy"))
        } footer: {
            Text(t(
                "로그인도 서버도 없습니다. 기록은 이 기기와 사용자의 iCloud에만 있습니다.",
                "There is no sign-in and no server. Your records live only on this device and in your own iCloud."
            ))
        }
    }

    // MARK: - 위기 상담

    private var safetySection: some View {
        Section {
            ForEach(Janjan.crisisContactsForCurrentRegion) { contact in
                Button {
                    call(contact)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.title(JanjanLanguage.current))
                                .foregroundStyle(Color.ink)
                            Text(contact.subtitle(JanjanLanguage.current))
                                .janjanBody(12)
                                .foregroundStyle(Color.muted)
                        }
                        Spacer()
                        Text(contact.number)
                            .foregroundStyle(Color.ink2)
                            .monospacedDigit()
                    }
                }
            }
        } header: {
            Text(t("위기 상담", "Crisis support"))
        } footer: {
            Text(t("응급 상황은 112 · 119.", "For emergencies: 112 · 119."))
        }
    }

    private func call(_ contact: Janjan.CrisisContact) {
        guard let url = URL(string: "tel://\(contact.dialDigits)") else { return }
        openURL(url)
    }

    // MARK: - 기타

    private var aboutSection: some View {
        Section {
            // 원본은 저장소의 docs/site/, GitHub Pages 로 낸다.
            if let url = URL(string: Janjan.privacyPolicyURLString) {
                Link(t("개인정보처리방침", "Privacy Policy"), destination: url)
                    .foregroundStyle(Color.ink)
            }
            if let url = URL(string: Janjan.supportURLString) {
                Link(t("지원 · 자주 묻는 질문", "Support · FAQ"), destination: url)
                    .foregroundStyle(Color.ink)
            }
            if let url = URL(string: Janjan.termsURLString) {
                Link(t("이용약관", "Terms of Use"), destination: url)
                    .foregroundStyle(Color.ink)
            }
            Button(t("오픈소스 라이선스", "Open source licenses")) {
                isShowingLicenses = true
            }
            .foregroundStyle(Color.ink)
            LabeledContent(t("버전", "Version")) {
                Text(appVersionText)
                    .foregroundStyle(Color.muted)
                    .monospacedDigit()
            }
        } header: {
            Text(t("기타", "More"))
        } footer: {
            Text(Janjan.medicalDisclaimer(JanjanLanguage.current))
        }
    }

    /// iCloud 를 쓰는 중이면 삭제가 동기화를 타고 다른 기기에서도 사라진다.
    /// 그 사실을 누르기 전에 말해 준다.
    private var deleteWarningKo: String {
        let base = t("되돌릴 수 없습니다. 기록·약·설정이 모두 사라집니다.", "This cannot be undone. Records, medications, and settings will all be gone.")
        guard JanjanModelContainer.activeStorage == .cloudKit else { return base }
        return base + " " + t("iCloud 로 연결된 다른 기기에서도 사라집니다.", "It will also disappear from other devices connected through iCloud.")
    }

    /// 저장된 것을 전부 지운다.
    ///
    /// 지우는 순서가 중요하다. 알림을 먼저 걷어야 이미 예약된 알림이
    /// 사라진 약의 이름을 잠금화면에 띄우는 일이 없다.
    /// iCloud 레코드는 따로 부를 것이 없다 — SwiftData 가 지운 행이 그대로 동기화된다.
    private func deleteEverything() {
        NotificationManager.shared.cancelAllDoseReminders()
        MedicationStore.deleteEverything(in: context)

        // SwiftData 밖에도 기록이 남는다. 여기서 같이 걷지 않으면
        // "모두 사라집니다" 라고 적어 놓고 거짓말을 하는 셈이 된다.
        //
        //  · 내보낸 리포트 PDF — 약 이름·복약률·기분·의사에게 물어볼 말이 들어 있다.
        //  · 진료 질문 메모 — iCloud 로 안 넘어가는 대신 이 기기에 남는다.
        ReportPDF.removeExportedFiles()
        UserDefaults.standard.removeObject(forKey: ReportView.questionsDefaultsKey)

        // 잠금 번호도 설정이다. "설정이 모두 사라집니다" 라고 적어 놓고 남기지 않는다.
        // 키체인 항목은 앱을 지워도 남으므로, 여기서 걷지 않으면 새로 깔아도 따라온다.
        lock.disable()

        AppServices.shared.pushWatchSnapshot()
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

/// 번들 서체 고지 (SIL OFL 1.1).
///
/// 원본은 서체와 같은 폴더의 `OFL-NOTICE.txt` 다. 파일 하나만 두고 화면이 그걸 읽는다 —
/// 같은 문구를 코드에도 적어 두면 서체를 갈아 끼울 때 한쪽만 고치게 된다.
private struct LicenseNoticeView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(noticeText)
                    .janjanBody(13)
                    .foregroundStyle(Color.ink2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(CGFloat(JanjanSpacing.m))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle(t("오픈소스 라이선스", "Open source licenses"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
        }
    }

    /// 번들 안 OFL-NOTICE.txt 는 원문(한국어) 그대로 낸다 — 라이선스 고지문 자체는
    /// 번역 대상이 아니고, 없을 때만 앱이 들고 있는 대체 문구를 언어에 맞춰 보여 준다.
    private var noticeText: String {
        guard let url = Bundle.main.url(forResource: "OFL-NOTICE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return t(Self.fallbackKo, Self.fallbackEn) }
        return text
    }

    /// 번들에서 못 찾았을 때도 고지 없이 넘어가지는 않는다 — OFL 이 요구하는 것이다.
    private static let fallbackKo = """
    번들 서체 라이선스 고지 (SIL Open Font License 1.1)

    Pretendard (c) Kil Hyung-jin — https://github.com/orioncactus/pretendard
    SUIT (c) SUNN — https://github.com/sun-typeface/SUIT

    두 서체 모두 SIL Open Font License 1.1 로 배포됩니다.
    전문: https://openfontlicense.org
    """

    private static let fallbackEn = """
    Bundled font license notice (SIL Open Font License 1.1)

    Pretendard (c) Kil Hyung-jin — https://github.com/orioncactus/pretendard
    SUIT (c) SUNN — https://github.com/sun-typeface/SUIT

    Both fonts are distributed under the SIL Open Font License 1.1.
    Full text: https://openfontlicense.org
    """
}

#Preview {
    SettingsView()
        .environmentObject(AppLockManager())
        .environmentObject(ProStore())
        .modelContainer(for: JanjanSchema.allModels, inMemory: true)
}
