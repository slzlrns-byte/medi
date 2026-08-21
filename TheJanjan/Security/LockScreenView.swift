import Combine
import SwiftUI
import JanjanCore

/// 잠금 화면. 앱 내용 위에 그대로 덮는다.
///
/// 아무것도 보여 주지 않는 것이 이 화면의 일이다. 워드마크와 숫자판만 둔다.
/// 이 화면이 어깨너머로 보여도 투약 앱임이 드러나지 않아야 한다(설계 01절).
struct LockScreenView: View {

    @EnvironmentObject private var lock: AppLockManager

    @State private var digits = ""
    @State private var shake = 0
    /// 기다리는 동안 남은 시간을 1초마다 다시 그리기 위한 시계.
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: CGFloat(JanjanSpacing.xl)) {
            Spacer()
            wordmark

            PasscodeField(digits: $digits, onComplete: submit, isDisabled: lock.isThrottled)
                .modifier(ShakeEffect(animatableData: CGFloat(shake)))

            message
            Spacer()
            recoveryBlock
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, CGFloat(JanjanSpacing.l))
        .padding(.bottom, CGFloat(JanjanSpacing.xl))
        .background(Color.fog.ignoresSafeArea())
        .onReceive(tick) { now = $0 }
        .task {
            // Face ID 를 쓰기로 했으면 열자마자 한 번 물어본다.
            // 실패하거나 취소해도 숫자판이 그대로 남아 있으니 막다른 길이 아니다.
            if lock.canUseBiometricsNow, !lock.isThrottled {
                await lock.unlockWithDevice()
            }
        }
    }

    private var wordmark: some View {
        VStack(spacing: CGFloat(JanjanSpacing.xs)) {
            Text(Janjan.appNameKo)
                .font(JanjanFont.display(36))
                .foregroundStyle(Color.ink)
            Text(Janjan.sloganKo)
                .font(JanjanFont.body(13))
                .foregroundStyle(Color.muted)
        }
    }

    /// 실패 사유나 남은 기다림. 자리를 늘 비워 두어 글이 뜰 때 화면이 튀지 않게 한다.
    private var message: some View {
        Text(messageText)
            .font(JanjanFont.body(13))
            .foregroundStyle(Color.ink2)
            .multilineTextAlignment(.center)
            .frame(minHeight: 34)
            .padding(.horizontal, CGFloat(JanjanSpacing.l))
    }

    private var messageText: String {
        // `now` 를 읽어 1초마다 남은 시간이 다시 계산되게 한다.
        _ = now
        if lock.isThrottled {
            return PasscodeThrottle.messageKo(forRemaining: lock.remainingLockout) ?? ""
        }
        return lock.failureMessageKo ?? ""
    }

    private var recoveryBlock: some View {
        VStack(spacing: CGFloat(JanjanSpacing.m)) {
            if lock.canUseBiometricsNow, !lock.isThrottled {
                Button {
                    Task { await lock.unlockWithDevice() }
                } label: {
                    HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                        Image(systemName: lock.biometrySymbolName)
                            .font(.system(size: 16, weight: .regular))
                        Text("생체인식으로 열기")
                            .font(JanjanFont.body(15, weight: .medium))
                    }
                    .foregroundStyle(Color.ink)
                }
                .buttonStyle(.plain)
                .disabled(lock.isAuthenticating)
            }

            // 되찾는 길. 기다리는 중에도 열어 둔다 — 여기가 막히면 되찾을 곳이 없다.
            if lock.canRecoverWithDevice {
                Button("번호를 잊으셨어요?") {
                    Task { await lock.unlockWithDevice(forRecovery: true) }
                }
                .font(JanjanFont.body(13))
                .foregroundStyle(Color.muted)
                .disabled(lock.isAuthenticating)
            }
        }
    }

    private func submit(_ entered: String) {
        if lock.unlock(with: entered) {
            digits = ""
        } else {
            withAnimation(.default) { shake += 1 }
            digits = ""
        }
    }
}

/// 틀렸을 때 좌우로 한 번 흔든다. 소리도 붉은색도 쓰지 않는다 —
/// 틀린 것은 잘못이 아니고, 곁에서 보는 사람에게 알릴 일도 아니다.
private struct ShakeEffect: GeometryEffect {

    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let travel = 8 * sin(animatableData * .pi * 3)
        return ProjectionTransform(CGAffineTransform(translationX: travel, y: 0))
    }
}

#Preview {
    LockScreenView()
        .environmentObject(AppLockManager())
}
