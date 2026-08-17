import Combine
import Foundation
import LocalAuthentication
import SwiftUI
import JanjanCore

/// 앱 잠금. 무료 기능이고, 켤지 말지는 사용자가 고른다(설계 06절 무료/Pro 경계).
///
/// 앱만의 비밀번호를 따로 만들지 않는다. `.deviceOwnerAuthentication` 정책 하나로
/// Face ID · Touch ID 를 먼저 띄우고, 안 되면 기기 암호로 떨어진다. 그래서 사용자가
/// 외울 것이 없고, 생체 정보는 앱에 들어오지 않는다(성공·실패만 받는다).
///
/// "다시 잠글 때가 되었는지"의 판단은 JanjanCore 의 `LockPolicy` 가 하고,
/// 여기서는 LocalAuthentication 과 앱 생애주기만 다룬다.
@MainActor
final class AppLockManager: ObservableObject {

    // MARK: - 저장되는 설정
    //
    // @AppStorage 를 뷰가 아닌 클래스에서 쓰면 값은 제대로 오가지만 objectWillChange 가
    // 울리지 않는다. 그래서 저장은 @AppStorage 에 맡기고, 바깥에 내보내는 창구는
    // 계산 프로퍼티로 감싸 쓸 때마다 직접 알린다. 이걸 빼먹으면 설정 화면의 토글이
    // 손가락을 따라오지 않는다.

    @AppStorage("appLockEnabled") private var storedIsEnabled = false
    @AppStorage("appLockDiaryOnly") private var storedDiaryOnly = false
    @AppStorage("appLockGraceSeconds") private var storedGraceSeconds = LockPolicy.defaultGraceSeconds

    /// 잠금이 켜져 있던 채로 앱이 새로 떴다면 잠긴 상태로 시작한다.
    /// 위 `appLockEnabled` 와 같은 키다 — 한쪽만 고치지 말 것.
    @Published var isLocked: Bool = UserDefaults.standard.bool(forKey: "appLockEnabled")

    /// 인증 시트가 떠 있는 동안 두 번 띄우지 않기 위한 표시.
    @Published private(set) var isAuthenticating = false

    /// 사용자에게 보여 줄 만한 실패 사유. 스스로 취소한 경우에는 아무 말도 하지 않는다(`nil`).
    @Published private(set) var failureMessageKo: String?

    /// 마지막으로 화면에서 사라진 시각. 유예 시간을 재는 기준점.
    private var lastBackgroundedAt: Date?

    /// `@MainActor` 클래스의 암묵적 초기화 함수는 메인 액터에 묶여서,
    /// `App` 의 프로퍼티 초깃값에서 부를 때 걸린다. 아무것도 만지지 않는 init 을 열어 둔다.
    nonisolated init() {}

    // MARK: - 바깥에 내보내는 설정

    /// 잠금이 켜져 있는지. 켜고 끄는 것은 `setEnabled(_:)` 로만 — 켤 때 확인이 필요하다.
    var isEnabled: Bool { storedIsEnabled }

    /// 켜면 기록(일기) 탭만 잠근다. 오늘·약·리포트는 그대로 열린다.
    var diaryOnly: Bool {
        get { storedDiaryOnly }
        set {
            objectWillChange.send()
            storedDiaryOnly = newValue
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

    /// 잠금 화면 버튼에 쓸 SF Symbol.
    var biometrySymbolName: String {
        let context = LAContext()
        // biometryType 은 canEvaluatePolicy 를 한 번 부른 뒤에야 채워진다.
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock"
        }
    }

    // MARK: - 앱 생애주기

    /// 씬 단계가 바뀔 때 한 곳에서 받는다.
    func handle(scenePhase phase: ScenePhase) {
        if phase == .active {
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
        guard storedIsEnabled else { return }

        let now = Date()
        if lastBackgroundedAt == nil {
            lastBackgroundedAt = now
        }
        if LockPolicy.shouldLock(
            now: now,
            lastBackgroundedAt: lastBackgroundedAt,
            graceSeconds: TimeInterval(storedGraceSeconds)
        ) {
            isLocked = true
        }
    }

    /// 다시 앞으로 나올 때. 유예가 지났으면 잠근다.
    func lockIfGracePassed() {
        guard storedIsEnabled else {
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
            isLocked = true
        }
        // 다음 외출은 새 시계로 잰다.
        lastBackgroundedAt = nil
    }

    // MARK: - 잠금 해제

    /// 성공하면 잠금을 푼다. 실패해도 던지지 않는다 — 잠금 화면이 그대로 남아 있으면 된다.
    @discardableResult
    func authenticate() async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "취소"

        // 생체인식이 없거나 등록되지 않아도 이 정책이면 기기 암호로 떨어진다.
        // 그래서 여기서 false 가 나오는 경우는 사실상 "기기 암호조차 없다" 하나뿐이다.
        // 그 기기에서 잠금을 붙잡고 있으면 사용자가 자기 기록에서 잠겨 나가므로,
        // 잠금을 풀고 설정도 끈다.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            failureMessageKo = "이 기기에는 잠금을 열 방법이 없어요. 기기 설정에서 암호를 먼저 만들어 주세요."
            store(isEnabled: false)
            isLocked = false
            lastBackgroundedAt = nil
            return false
        }

        do {
            // 성공하면 그대로 돌아오고, 실패·취소는 LAError 로 던져진다.
            // (돌려주는 Bool 은 오류 없이 false 가 되는 경우가 없어 쓰지 않는다.)
            _ = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "더잔잔 잠금을 해제합니다"
            )
            failureMessageKo = nil
            lastBackgroundedAt = nil
            isLocked = false
            return true
        } catch let error as LAError {
            failureMessageKo = Self.messageKo(forCode: error.code)
            return false
        } catch {
            failureMessageKo = "지금은 잠금을 해제할 수 없어요. 잠시 후 다시 시도해 주세요."
            return false
        }
    }

    /// 설정에서 잠금을 켜고 끈다.
    ///
    /// 켤 때는 먼저 한 번 열어 본다. 열리지 않는 기기에서 잠금이 켜지면
    /// 사용자가 자기 기록에서 잠겨 나가기 때문이다. 확인에 실패하면 켜지 않는다.
    func setEnabled(_ enabled: Bool) async {
        guard enabled != storedIsEnabled else { return }

        if enabled {
            if await authenticate() {
                store(isEnabled: true)
                isLocked = false
            } else {
                // 켜지 않는다. 토글이 제자리로 돌아가도록 화면을 한 번 다시 그린다.
                objectWillChange.send()
            }
        } else {
            store(isEnabled: false)
            failureMessageKo = nil
            isLocked = false
            lastBackgroundedAt = nil
        }
    }

    // MARK: - 안쪽

    private func store(isEnabled: Bool) {
        objectWillChange.send()
        storedIsEnabled = isEnabled
    }

    /// LAError 는 사용자가 취소한 것까지 오류로 알려 준다. 취소는 잘못이 아니므로 `nil`.
    private static func messageKo(forCode code: LAError.Code) -> String? {
        switch code {
        case .userCancel, .appCancel, .systemCancel:
            return nil
        case .authenticationFailed:
            return "확인하지 못했어요. 다시 시도하거나 기기 암호로 열어 주세요."
        case .biometryLockout:
            return "생체인식이 잠겼어요. 기기 암호로 열어 주세요."
        case .biometryNotAvailable, .biometryNotEnrolled:
            return "이 기기에서는 기기 암호로 열어 주세요."
        case .passcodeNotSet:
            return "기기 설정에서 암호를 먼저 만들어 주세요."
        default:
            return "지금은 잠금을 해제할 수 없어요. 잠시 후 다시 시도해 주세요."
        }
    }
}
