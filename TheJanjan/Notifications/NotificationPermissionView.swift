import SwiftUI
import UserNotifications
import JanjanCore

/// 알림 권한을 묻기 전에 왜 필요한지 한 문장 보여 주는 화면.
///
/// 시스템 창을 아무 맥락 없이 띄우지 않는다. 한 번 거절당하면 앱 안에서는 되돌릴 수
/// 없고 사용자가 iOS 설정까지 찾아가야 하기 때문에, 물어볼 자리를 고르는 것이 중요하다.
/// 그 자리는 **첫 약을 시간과 함께 등록한 직후**다 — 그때 알림이 처음으로 뜻을 갖는다.
///
/// 거절해도 앱은 완전히 동작한다. 알림은 거들 뿐이고, 기록은 사용자가 직접 남긴다.
struct NotificationPermissionView: View {

    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isAsking = false

    var body: some View {
        VStack(spacing: CGFloat(JanjanSpacing.l)) {
            Spacer()

            CircleGlyph(systemImage: "bell", background: .butter, foreground: .butterInk, diameter: 72)

            VStack(spacing: CGFloat(JanjanSpacing.s)) {
                Text("약 시간에 알려드릴까요?")
                    .font(JanjanFont.display(26))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)

                Text("알림에서 바로 복용함·건너뜀을 누를 수 있어요. 앱을 열지 않아도 기록됩니다.")
                    .font(JanjanFont.body(15))
                    .foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("나중에 설정에서 켜고 끌 수 있어요.")
                    .font(JanjanFont.body(13))
                    .foregroundStyle(Color.muted)
                    .padding(.top, CGFloat(JanjanSpacing.xxs))
            }
            .padding(.horizontal, CGFloat(JanjanSpacing.m))

            Spacer()

            VStack(spacing: CGFloat(JanjanSpacing.s)) {
                BlackPillButton(title: "알림 받기", isBusy: isAsking) {
                    ask()
                }

                Button("지금은 괜찮아요") {
                    finish()
                }
                .font(JanjanFont.body(15))
                .foregroundStyle(Color.muted)
                .disabled(isAsking)
            }
        }
        .padding(.horizontal, CGFloat(JanjanSpacing.l))
        .padding(.bottom, CGFloat(JanjanSpacing.xl))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fogBackground()
        .interactiveDismissDisabled(isAsking)
    }

    private func ask() {
        isAsking = true
        Task {
            _ = await NotificationManager.shared.requestAuthorization()
            isAsking = false
            finish()
        }
    }

    private func finish() {
        onFinished()
        dismiss()
    }
}

/// 알림 권한을 언제 물었는지 기억하는 곳.
///
/// 시스템에 "아직 안 물어봤음(notDetermined)" 상태가 있지만, 그것만 믿으면
/// 사용자가 "지금은 괜찮아요" 를 누른 뒤에도 약을 등록할 때마다 다시 묻게 된다.
enum NotificationPermissionGate {

    private static let askedKey = "notificationPermissionAsked"

    static var hasAsked: Bool {
        get { UserDefaults.standard.bool(forKey: askedKey) }
        set { UserDefaults.standard.set(newValue, forKey: askedKey) }
    }

    /// 지금 물어봐야 하는가. 한 번이라도 물었으면 다시 묻지 않는다.
    static func shouldAsk() async -> Bool {
        guard !hasAsked else { return false }
        return await NotificationManager.shared.authorizationStatus() == .notDetermined
    }
}
