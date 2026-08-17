import SwiftUI
import JanjanCore

/// 설정 — 오늘 탭 우상단 톱니에서 올라온다 (설계 03절).
struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage("janjan.appLock.enabled") private var isAppLockEnabled = false
    @AppStorage("janjan.notifications.hideMedicationNames") private var hidesMedicationNames = false

    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                notificationsSection
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

    // MARK: - 보안 · 개인정보

    private var privacySection: some View {
        Section {
            Toggle("앱 잠금 (Face ID)", isOn: $isAppLockEnabled)

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
            Text("보안 · 개인정보")
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
            Button("개인정보처리방침") {
                // TODO: GitHub Pages 주소가 정해지면 연결한다.
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
}
