import Combine
import Foundation
import LocalAuthentication
import SwiftUI
import JanjanCore

/// 앱 잠금. 무료 기능이고, 켤지 말지는 사용자가 고른다(설계 06절 무료/Pro 경계).
///
/// 앱을 열면 **네 자리 번호**를 누른다. Face ID · Touch ID 는 매번 누르지 않아도 되게
/// 해 주는 지름길이고, 동시에 **번호를 잊었을 때 되찾는 길**이다.
///
/// 되찾는 길이 이 파일에서 가장 중요하다. 이 앱에는 서버도 계정도 없어서
/// 잠긴 것을 풀어 줄 곳이 없다. 번호만 있고 되찾을 길이 없으면, 번호를 잊은 사람은
/// 자기 투약 기록을 영영 잃는다. 그래서 기기 인증을 늘 곁문으로 열어 둔다 —
/// 기기가 곧 열쇠라 사용자가 새로 외울 것은 늘지 않는다.
///
/// "다시 잠글 때가 되었는지" 는 `LockPolicy`, 번호의 모양과 기다림은 `Passcode` ·
/// `PasscodeThrottle` 가 판단한다. 여기서는 키체인·LocalAuthentication·생애주기만 다룬다.
@MainActor
final class AppLockManager: ObservableObject {

    // MARK: - 저장되는 설정
    //
    // @AppStorage 를 뷰가 아닌 클래스에서 쓰면 값은 제대로 오가지만 objectWillChange 가
    // 울리지 않는다. 그래서 저장은 @AppStorage 에 맡기고, 바깥에 내보내는 창구는
    // 계산 프로퍼티로 감싸 쓸 때마다 직접 알린다. 이걸 빼먹으면 설정 화면의 토글이
    // 손가락을 따라오지 않는다.

    @AppStorage("appLockGraceSeconds") private var storedGraceSeconds = LockPolicy.defaultGraceSeconds
    @AppStorage("appLockUsesBiometrics") private var storedUsesBiometrics = true

    /// 틀린 횟수와 마지막으로 틀린 시각. 앱을 껐다 켜도 기다림이 이어지도록 남긴다.
    @AppStorage("appLockFailedAttempts") private var storedFailedAttempts = 0
    @AppStorage("appLockLastFailureAt") private var storedLastFailureAt = 0.0

    /// 잠금이 켜져 있는가. **저장된 번호가 있다는 것이 곧 켜져 있다는 뜻이다.**
    /// 켜짐 여부를 따로 두면 둘이 어긋나는 날이 오고, 그날 사용자는 열 수 없는 잠금 앞에 선다.
    ///
    /// 키체인을 뷰 본문에서 매번 읽지 않으려고 값을 들고 있는다. 번호를 정하거나 끌 때만
    /// 바뀌므로 그 두 곳에서만 다시 맞춘다.
    @Published private(set) var isEnabled: Bool = PasscodeStore.isSet

    /// 잠금이 켜져 있던 채로 앱이 새로 떴다면 잠긴 상태로 시작한다.
    @Published var isLocked: Bool = PasscodeStore.isSet

    /// 인증 시트가 떠 있는 동안 두 번 띄우지 않기 위한 표시.
    @Published private(set) var isAuthenticating = false

    /// 사용자에게 보여 줄 만한 실패 사유. 스스로 취소한 경우에는 아무 말도 하지 않는다(`nil`).
    @Published private(set) var failureMessageKo: String?

    /// 기기 인증으로 되찾아 들어왔다. 새 번호를 정해야 한다.
    @Published var needsNewPasscode = false

    /// 마지막으로 화면에서 사라진 시각. 유예 시간을 재는 기준점.
    private var lastBackgroundedAt: Date?

    /// `@MainActor` 클래스의 암묵적 초기화 함수는 메인 액터에 묶여서,
    /// `App` 의 프로퍼티 초깃값에서 부를 때 걸린다. 아무것도 만지지 않는 init 을 열어 둔다.
    nonisolated init() {}

    // MARK: - 바깥에 내보내는 설정

    /// Face ID · Touch ID 로도 열지. 꺼도 번호로는 언제나 열린다.
    var usesBiometrics: Bool {
        get { storedUsesBiometrics }
        set {
            objectWillChange.send()
            storedUsesBiometrics = newValue
        }
    }

    /// 화면에서 사라진 뒤 이 시간이 지나면 다시 잠근다. 기본값 0초.
    var graceSeconds: Int {
        get { storedGraceSeconds }
        set {
            objectWillChange.send()
            storedGraceSeconds = newValue
        }
    }

    // MARK: - 기기가 할 수 있는 것
    //
    // LAContext 를 만들고 canEvaluatePolicy 를 부르는 일을 뷰 본문에서 하면
    // 화면을 다시 그릴 때마다 되풀이된다. 앱 밖(기기 설정)에서만 바뀌는 값이라
    // 한 번 재어 두고 앱이 앞으로 나올 때 다시 잰다.

    // 초깃값에서는 `Self.` 를 쓸 수 없어(final 이어도 막힌다) 타입 이름을 그대로 적는다.
    @Published private(set) var canRecoverWithDevice = AppLockManager.deviceAuthAvailable()
    @Published private(set) var biometrySymbolName = AppLockManager.biometrySymbol()
    @Published private(set) var hasBiometry = AppLockManager.biometryAvailable()

    /// 생체인식을 지금 쓸 수 있는가. 설정에서 껐거나 등록돼 있지 않으면 거짓.
    var canUseBiometricsNow: Bool { storedUsesBiometrics && hasBiometry }

    /// 기기 설정에서 Face ID 를 등록하거나 암호를 지우고 돌아왔을 수 있다.
    func refreshDeviceCapabilities() {
        canRecoverWithDevice = AppLockManager.deviceAuthAvailable()
        biometrySymbolName = AppLockManager.biometrySymbol()
        hasBiometry = AppLockManager.biometryAvailable()
    }

    // 아래 셋은 프로퍼티 초깃값에서 불린다. @MainActor 클래스의 static 은 기본으로
    // 메인 액터에 묶이는데, nonisolated init 에서는 그것을 부를 수 없어 풀어 둔다.

    private nonisolated static func deviceAuthAvailable() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    private nonisolated static func biometryAvailable() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    private nonisolated static func biometrySymbol() -> String {
        let context = LAContext()
        // biometryType 은 canEvaluatePolicy 를 한 번 부른 뒤에야 채워진다.
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock"
        }
    }

    // MARK: - 기다림

    private var lastFailureAt: Date? {
        storedLastFailureAt > 0 ? Date(timeIntervalSince1970: storedLastFailureAt) : nil
    }

    /// 지금 몇 초를 더 기다려야 하는가.
    var remainingLockout: TimeInterval {
        PasscodeThrottle.remainingLockout(
            now: Date(),
            lastFailureAt: lastFailureAt,
            failedAttempts: storedFailedAttempts
        )
    }

    var isThrottled: Bool { remainingLockout > 0 }

    // MARK: - 앱 생애주기

    /// 씬 단계가 바뀔 때 한 곳에서 받는다.
    func handle(scenePhase phase: ScenePhase) {
        if phase == .active {
            refreshDeviceCapabilities()
            lockIfGracePassed()
        } else {
            lockIfNeeded()
        }
    }

    /// 화면에서 사라질 때(백그라운드·비활성). 유예가 0이면 여기서 곧바로 잠근다.
    ///
    /// 나간 시각은 처음 한 번만 적는다. 다시 앞으로 나올 때도
    /// `.inactive` 를 한 번 거치는데, 그때 덮어써 버리면 유예를 영원히 다시 세게 된다.
    func lockIfNeeded() {
        guard isEnabled else { return }

        let now = Date()
        if lastBackgroundedAt == nil {
            lastBackgroundedAt = now
        }
        if LockPolicy.shouldLock(
            now: now,
            lastBackgroundedAt: lastBackgroundedAt,
            graceSeconds: TimeInterval(storedGraceSeconds)
        ) {
            lock()
        }
    }

    /// 다시 앞으로 나올 때. 유예가 지났으면 잠근다.
    func lockIfGracePassed() {
        guard isEnabled else {
            lastBackgroundedAt = nil
            return
        }
        // 나간 적이 없으면(설정에서 방금 켠 경우 등) 그대로 둔다.
        guard let leftAt = lastBackgroundedAt else { return }

        if LockPolicy.shouldLock(
            now: Date(),
            lastBackgroundedAt: leftAt,
            graceSeconds: TimeInterval(storedGraceSeconds)
        ) {
            lock()
        }
        // 다음 외출은 새 시계로 잰다.
        lastBackgroundedAt = nil
    }

    private func lock() {
        isLocked = true
        // 잠글 때 하던 말은 지운다. 다음에 열 때 지난번 실패 문구가 남아 있으면
        // 방금 무언가 잘못한 것처럼 보인다.
        failureMessageKo = nil
    }

    // MARK: - 번호로 열기

    /// 네 자리를 받아 연다.
    ///
    /// 기다리는 중이면 세어 보지도 않는다 — 기다림을 눌러서 넘길 수 없어야 한다.
    @discardableResult
    func unlock(with pin: String) -> Bool {
        guard !isThrottled else {
            failureMessageKo = PasscodeThrottle.messageKo(forRemaining: remainingLockout)
            return false
        }

        guard PasscodeStore.verify(pin) else {
            recordFailure()
            return false
        }

        clearFailures()
        failureMessageKo = nil
        lastBackgroundedAt = nil
        isLocked = false
        return true
    }

    private func recordFailure() {
        objectWillChange.send()
        storedFailedAttempts += 1
        storedLastFailureAt = Date().timeIntervalSince1970

        let waiting = remainingLockout
        if let message = PasscodeThrottle.messageKo(forRemaining: waiting) {
            failureMessageKo = message
        } else {
            // 남은 횟수를 세어 보이지 않는다. 세어 보이면 재촉이 되고,
            // 곁에서 보는 사람에게는 얼마나 더 눌러 볼 수 있는지 알려 주는 셈이 된다.
            failureMessageKo = "번호가 맞지 않아요."
        }
    }

    private func clearFailures() {
        objectWillChange.send()
        storedFailedAttempts = 0
        storedLastFailureAt = 0
    }

    // MARK: - 기기 인증으로 열기 · 되찾기

    /// Face ID · Touch ID · 기기 암호로 연다.
    ///
    /// - Parameter forRecovery: 번호를 잊어 되찾는 길로 들어온 경우. 열리면 새 번호를 정하게 한다.
    @discardableResult
    func unlockWithDevice(forRecovery: Bool = false) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "취소"

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            failureMessageKo = forRecovery
                ? "이 기기에는 잠금을 열 방법이 없어요. 번호로 열어 주세요."
                : nil
            return false
        }

        do {
            _ = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: forRecovery ? "새 번호를 정하기 위해 확인합니다" : "더잔잔 잠금을 해제합니다"
            )
            clearFailures()
            failureMessageKo = nil
            lastBackgroundedAt = nil
            isLocked = false
            // 되찾아 들어왔으면 새 번호를 정하게 한다. 잊은 번호를 그대로 두면
            // 다음에 앱을 열 때 같은 자리에서 또 막힌다.
            if forRecovery { needsNewPasscode = true }
            return true
        } catch let error as LAError {
            failureMessageKo = Self.messageKo(forCode: error.code)
            return false
        } catch {
            failureMessageKo = "지금은 확인할 수 없어요. 잠시 후 다시 해 주세요."
            return false
        }
    }

    // MARK: - 번호 정하기 · 끄기

    /// 번호를 새로 정하거나 바꾼다. 성공하면 잠금이 켜진다.
    @discardableResult
    func setPasscode(_ pin: String) -> Bool {
        guard Passcode.validate(pin) == .ok else { return false }
        guard PasscodeStore.save(pin) else {
            failureMessageKo = "번호를 저장하지 못했어요. 잠시 후 다시 해 주세요."
            return false
        }
        clearFailures()
        isEnabled = true
        failureMessageKo = nil
        needsNewPasscode = false
        isLocked = false
        lastBackgroundedAt = nil
        return true
    }

    /// 잠금을 끈다. 지금 열려 있는 상태에서만 부른다.
    func disable() {
        PasscodeStore.remove()
        clearFailures()
        isEnabled = false
        failureMessageKo = nil
        needsNewPasscode = false
        isLocked = false
        lastBackgroundedAt = nil
    }

    // MARK: - 안쪽

    /// LAError 는 사용자가 취소한 것까지 오류로 알려 준다. 취소는 잘못이 아니므로 `nil`.
    private static func messageKo(forCode code: LAError.Code) -> String? {
        switch code {
        case .userCancel, .appCancel, .systemCancel:
            return nil
        case .authenticationFailed:
            return "확인하지 못했어요. 번호로 열어 주세요."
        case .biometryLockout:
            return "생체인식이 잠겼어요. 번호나 기기 암호로 열어 주세요."
        case .biometryNotAvailable, .biometryNotEnrolled:
            return "이 기기에서는 번호로 열어 주세요."
        case .passcodeNotSet:
            return "이 기기에는 암호가 없어요. 번호로 열어 주세요."
        default:
            return "지금은 확인할 수 없어요. 잠시 후 다시 해 주세요."
        }
    }
}
