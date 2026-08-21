import SwiftUI
import JanjanCore

/// 번호를 정하는 화면. 처음 켤 때, 바꿀 때, 되찾은 뒤 새로 정할 때 모두 이 화면이다.
///
/// 두 번 누르게 한다. 한 번만 받으면 잘못 누른 네 자리가 그대로 굳고,
/// 이 앱에는 그것을 풀어 줄 서버가 없다.
struct PasscodeSetupView: View {

    enum Mode: String, Identifiable {
        /// 처음 켜는 경우.
        case create
        /// 이미 켜져 있고 바꾸는 경우. 지금 번호를 먼저 확인한다.
        case change
        /// 기기 인증으로 되찾아 들어와 새로 정하는 경우. 지금 번호는 묻지 않는다.
        case reset

        var id: String { rawValue }

        var titleKo: String {
            switch self {
            case .create: return "잠금 켜기"
            case .change: return "번호 바꾸기"
            case .reset: return "새 번호 정하기"
            }
        }
    }

    let mode: Mode
    let onDone: () -> Void

    @EnvironmentObject private var lock: AppLockManager
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .current
    @State private var digits = ""
    @State private var firstEntry = ""
    @State private var messageKo: String?
    @State private var isEasyGuess = false
    @State private var shake = 0

    private enum Step {
        /// 지금 쓰는 번호 확인 (바꾸기일 때만).
        case current
        /// 새 번호.
        case fresh
        /// 새 번호 한 번 더.
        case confirm
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: CGFloat(JanjanSpacing.xl)) {
                header

                PasscodeField(digits: $digits, onComplete: submit)
                    .modifier(ShakeEffect(animatableData: CGFloat(shake)))

                message
                Spacer()
                recoveryHint
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, CGFloat(JanjanSpacing.l))
            .padding(.top, CGFloat(JanjanSpacing.l))
            .padding(.bottom, CGFloat(JanjanSpacing.xl))
            .fogBackground()
            .navigationTitle(mode.titleKo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // 되찾은 뒤에는 물러날 곳이 없다. 새 번호를 정해야 앱을 쓸 수 있다.
                    if mode != .reset {
                        Button("취소") {
                            onDone()
                            dismiss()
                        }
                        .foregroundStyle(Color.ink)
                    }
                }
            }
            .onAppear {
                step = (mode == .change) ? .current : .fresh
            }
        }
        .interactiveDismissDisabled(mode == .reset)
    }

    // MARK: - 조각

    private var header: some View {
        VStack(spacing: CGFloat(JanjanSpacing.xs)) {
            Text(promptKo)
                .font(JanjanFont.display(22))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
            Text(subtitleKo)
                .font(JanjanFont.body(13))
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, CGFloat(JanjanSpacing.m))
    }

    private var promptKo: String {
        switch step {
        case .current: return "지금 번호를 눌러 주세요"
        case .fresh: return "쓸 번호를 정해 주세요"
        case .confirm: return "한 번 더 눌러 주세요"
        }
    }

    private var subtitleKo: String {
        switch step {
        case .current:
            return "확인한 뒤에 새 번호를 정해요."
        case .fresh:
            return "앱을 열 때마다 이 네 자리를 눌러요."
        case .confirm:
            return "잘못 누른 번호가 굳지 않도록 한 번 더 받아요."
        }
    }

    private var message: some View {
        VStack(spacing: CGFloat(JanjanSpacing.xxs)) {
            if let messageKo {
                Text(messageKo)
                    .font(JanjanFont.body(13))
                    .foregroundStyle(Color.ink2)
            }
            if isEasyGuess {
                Text(Passcode.easyGuessMessageKo)
                    .font(JanjanFont.body(12))
                    .foregroundStyle(Color.muted)
            }
        }
        .multilineTextAlignment(.center)
        .frame(minHeight: 34)
        .padding(.horizontal, CGFloat(JanjanSpacing.l))
    }

    /// 되찾을 길이 없는 기기에서는 켜기 전에 그 사실을 말한다.
    /// 말없이 켜 두었다가 잊으면 기록을 통째로 잃는다.
    @ViewBuilder
    private var recoveryHint: some View {
        if !lock.canRecoverWithDevice {
            JanjanCard(padding: CGFloat(JanjanSpacing.m)) {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                    Text("이 기기에는 되찾을 길이 없어요")
                        .font(JanjanFont.body(14, weight: .medium))
                        .foregroundStyle(Color.ink)
                    Text("기기 암호나 Face ID 가 설정돼 있지 않아서, 번호를 잊으면 기록을 열 방법이 없어요. 기기 설정에서 암호를 먼저 만들어 두시길 권해요.")
                        .font(JanjanFont.body(12))
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text("번호를 잊으면 \(biometryWordKo)로 되찾을 수 있어요.")
                .font(JanjanFont.body(12))
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
        }
    }

    private var biometryWordKo: String {
        switch lock.biometrySymbolName {
        case "faceid": return "Face ID"
        case "touchid": return "Touch ID"
        default: return "기기 암호"
        }
    }

    // MARK: - 흐름

    private func submit(_ entered: String) {
        switch step {
        case .current:
            if lock.unlock(with: entered) {
                advance(to: .fresh)
            } else {
                reject("번호가 맞지 않아요.")
            }

        case .fresh:
            guard Passcode.validate(entered) == .ok else {
                reject(Passcode.validate(entered).messageKo)
                return
            }
            firstEntry = entered
            isEasyGuess = Passcode.isEasilyGuessed(entered)
            advance(to: .confirm)

        case .confirm:
            guard entered == firstEntry else {
                // 처음부터 다시. 어긋난 채로 굳는 것보다 한 번 더 받는 편이 낫다.
                firstEntry = ""
                isEasyGuess = false
                advance(to: .fresh)
                messageKo = "두 번이 서로 달라요. 다시 정해 주세요."
                withAnimation(.default) { shake += 1 }
                return
            }
            if lock.setPasscode(entered) {
                onDone()
                dismiss()
            } else {
                reject("번호를 저장하지 못했어요. 잠시 후 다시 해 주세요.")
            }
        }
    }

    private func advance(to next: Step) {
        step = next
        digits = ""
        messageKo = nil
    }

    private func reject(_ text: String?) {
        digits = ""
        messageKo = text
        withAnimation(.default) { shake += 1 }
    }
}

private struct ShakeEffect: GeometryEffect {

    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let travel = 8 * sin(animatableData * .pi * 3)
        return ProjectionTransform(CGAffineTransform(translationX: travel, y: 0))
    }
}

#Preview {
    PasscodeSetupView(mode: .create) {}
        .environmentObject(AppLockManager())
}
