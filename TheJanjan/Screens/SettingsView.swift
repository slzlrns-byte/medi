import SwiftUI
import SwiftData
import JanjanCore

/// 설정 — 오늘 탭 우상단 톱니에서 올라온다 (설계 03절).
struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var lock: AppLockManager
    @EnvironmentObject private var pro: ProStore

    @AppStorage(NotificationManager.hideNamesDefaultsKey) private var hidesMedicationNames = false

    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingPaywall = false
    @State private var isShowingLicenses = false

    var body: some View {
        NavigationStack {
            Form {
                proSection
                notificationsSection
                securitySection
                privacySection
                safetySection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.fog.ignoresSafeArea())
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView()
            }
            .confirmationDialog(
                "모든 데이터를 삭제할까요?",
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("삭제", role: .destructive) { deleteEverything() }
                Button("취소", role: .cancel) {}
            } message: {
                Text(deleteWarningKo)
            }
            .sheet(isPresented: $isShowingLicenses) {
                LicenseNoticeView()
            }
        }
    }

    // MARK: - Pro

    /// 심사자가 복원 버튼을 찾는 곳이기도 하다(심사 노트에 "복원은 설정 > Pro" 라고 적었다).
    private var proSection: some View {
        Section {
            LabeledContent("상태") {
                Text(pro.isPro ? "Pro 사용 중" : "무료")
                    .foregroundStyle(Color.muted)
            }

            Button("Pro 알아보기") {
                isShowingPaywall = true
            }
            .foregroundStyle(Color.ink)

            Button("구매 복원") {
                Task { await pro.restore() }
            }
            .foregroundStyle(Color.ink)
            .disabled(pro.isLoading)

            if pro.isPro, let url = URL(string: ProProduct.manageSubscriptionsURLString) {
                Link("구독 관리", destination: url)
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
            return "기간과 해지는 \"구독 관리\" 에서 확인할 수 있어요."
        }
        return "무료 기능은 구독 없이 계속 쓸 수 있어요."
    }

    // MARK: - 알림

    private var notificationsSection: some View {
        Section {
            Toggle("잠금화면에서 약 이름 숨기기", isOn: $hidesMedicationNames)
                .onChange(of: hidesMedicationNames) { _, _ in
                    // 이미 예약된 알림은 문구가 구워진 채로 남아 있다. 다시 깔아야 바뀐다.
                    Task { await ReminderPlanner.reschedule(using: context) }
                }
        } header: {
            Text("알림")
        } footer: {
            Text("켜면 알림에 \"취침 약 2종\" 처럼 개수만 보입니다.")
        }
    }

    // MARK: - 보안

    private var securitySection: some View {
        Section {
            Toggle("앱 잠금 (Face ID / 암호)", isOn: appLockBinding)

            if lock.isEnabled {
                Toggle("일기만 잠그기", isOn: diaryOnlyBinding)

                Picker("다시 잠그기", selection: graceSecondsBinding) {
                    ForEach(LockPolicy.allowedGraceSeconds, id: \.self) { seconds in
                        Text(LockPolicy.graceLabelKo(forSeconds: seconds)).tag(seconds)
                    }
                }
            }
        } header: {
            Text("보안")
        } footer: {
            Text(securityFooterKo)
        }
    }

    /// 켤 때는 먼저 한 번 열어 본다. 열리지 않으면 켜지 않는다 —
    /// 잠금 방법이 없는 기기에서 사용자가 자기 기록에서 잠겨 나가는 일을 막는다.
    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { lock.isEnabled },
            set: { wanted in Task { await lock.setEnabled(wanted) } }
        )
    }

    private var diaryOnlyBinding: Binding<Bool> {
        Binding(
            get: { lock.diaryOnly },
            set: { lock.diaryOnly = $0 }
        )
    }

    private var graceSecondsBinding: Binding<Int> {
        Binding(
            get: { lock.graceSeconds },
            set: { lock.graceSeconds = $0 }
        )
    }

    private var securityFooterKo: String {
        if let message = lock.failureMessageKo { return message }
        if lock.isEnabled {
            return "Face ID · Touch ID 또는 기기 암호로 열립니다. 일기만 잠그면 오늘 · 약 · 리포트는 그대로 열립니다."
        }
        return "Face ID · Touch ID 또는 기기 암호로 열립니다. 켤 때 한 번 확인해서, 열 수 없는 상태로 잠기는 일을 막습니다."
    }

    // MARK: - 개인정보

    private var privacySection: some View {
        Section {
            LabeledContent("저장 위치") {
                Text(JanjanModelContainer.activeStorage.labelKo)
                    .foregroundStyle(Color.muted)
            }

            Button(role: .destructive) {
                isShowingDeleteConfirmation = true
            } label: {
                Text("모든 데이터 삭제")
            }
        } header: {
            Text("개인정보")
        } footer: {
            Text("로그인도 서버도 없습니다. 기록은 이 기기와 사용자의 iCloud에만 있습니다.")
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
                            Text(contact.titleKo)
                                .foregroundStyle(Color.ink)
                            Text(contact.subtitleKo)
                                .font(JanjanFont.body(12))
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
            Text("위기 상담")
        } footer: {
            Text("응급 상황은 112 · 119.")
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
                Link("개인정보처리방침", destination: url)
                    .foregroundStyle(Color.ink)
            }
            if let url = URL(string: Janjan.supportURLString) {
                Link("지원 · 자주 묻는 질문", destination: url)
                    .foregroundStyle(Color.ink)
            }
            if let url = URL(string: Janjan.termsURLString) {
                Link("이용약관", destination: url)
                    .foregroundStyle(Color.ink)
            }
            Button("오픈소스 라이선스") {
                isShowingLicenses = true
            }
            .foregroundStyle(Color.ink)
            LabeledContent("버전") {
                Text(appVersionText)
                    .foregroundStyle(Color.muted)
                    .monospacedDigit()
            }
        } header: {
            Text("기타")
        } footer: {
            Text(Janjan.medicalDisclaimerKo)
        }
    }

    /// iCloud 를 쓰는 중이면 삭제가 동기화를 타고 다른 기기에서도 사라진다.
    /// 그 사실을 누르기 전에 말해 준다.
    private var deleteWarningKo: String {
        let base = "되돌릴 수 없습니다. 기록·약·설정이 모두 사라집니다."
        guard JanjanModelContainer.activeStorage == .cloudKit else { return base }
        return base + " iCloud 로 연결된 다른 기기에서도 사라집니다."
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
                    .font(JanjanFont.body(13))
                    .foregroundStyle(Color.ink2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(CGFloat(JanjanSpacing.m))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle("오픈소스 라이선스")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
        }
    }

    private var noticeText: String {
        guard let url = Bundle.main.url(forResource: "OFL-NOTICE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return Self.fallbackKo }
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
}

#Preview {
    SettingsView()
        .environmentObject(AppLockManager())
        .environmentObject(ProStore())
        .modelContainer(for: JanjanSchema.allModels, inMemory: true)
}
