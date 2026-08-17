import SwiftUI
import JanjanCore

/// 설정 — 오늘 탭 우상단 톱니에서 올라온다 (설계 03절).
struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var lock: AppLockManager
    @EnvironmentObject private var pro: ProStore

    @AppStorage("janjan.notifications.hideMedicationNames") private var hidesMedicationNames = false

    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingPaywall = false

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
                Button("삭제", role: .destructive) {
                    // TODO: SwiftData 저장소 전체 삭제 + iCloud 레코드 삭제
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("되돌릴 수 없습니다. 기록·약·설정이 모두 사라집니다.")
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
            ForEach(Janjan.crisisContactsKR) { contact in
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
                // TODO: SUIT · Pretendard (SIL OFL 1.1) 고지 화면
            }
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

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppLockManager())
        .environmentObject(ProStore())
}
