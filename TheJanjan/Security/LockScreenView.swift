import SwiftUI
import JanjanCore

/// 잠금 화면. 앱 내용 위에 그대로 덮는다.
///
/// 아무것도 보여 주지 않는 것이 이 화면의 일이다. 워드마크 하나와 검은 원 버튼 하나만 둔다.
/// 이 화면이 잠금화면에 떠도 투약 앱임이 드러나지 않아야 한다(설계 01절).
struct LockScreenView: View {

    @EnvironmentObject private var lock: AppLockManager

    var body: some View {
        VStack(spacing: CGFloat(JanjanSpacing.xxl)) {
            Spacer()
            wordmark
            unlockBlock
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fog.ignoresSafeArea())
        .task {
            // 화면이 올라오면 한 번 바로 물어본다. 실패하면 버튼이 남는다.
            await lock.authenticate()
        }
    }

    private var wordmark: some View {
        VStack(spacing: CGFloat(JanjanSpacing.xs)) {
            Text(Janjan.appNameKo)
                .font(JanjanFont.display(40))
                .foregroundStyle(Color.ink)
            Text(Janjan.sloganKo)
                .font(JanjanFont.body(14))
                .foregroundStyle(Color.muted)
        }
    }

    private var unlockBlock: some View {
        VStack(spacing: CGFloat(JanjanSpacing.s)) {
            BlackCircleButton(
                systemImage: lock.biometrySymbolName,
                accessibilityLabelKo: "잠금 해제",
                diameter: 72
            ) {
                Task { await lock.authenticate() }
            }
            .disabled(lock.isAuthenticating)

            Text("잠금 해제")
                .font(JanjanFont.body(15, weight: .medium))
                .foregroundStyle(Color.ink)

            Text("기기 암호로도 열 수 있어요")
                .font(JanjanFont.body(13))
                .foregroundStyle(Color.muted)

            if let message = lock.failureMessageKo {
                Text(message)
                    .font(JanjanFont.body(13))
                    .foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, CGFloat(JanjanSpacing.xl))
                    .padding(.top, CGFloat(JanjanSpacing.xxs))
            }
        }
    }
}

#Preview {
    LockScreenView()
        .environmentObject(AppLockManager())
}
