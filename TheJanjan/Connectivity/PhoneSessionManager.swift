import Foundation
import OSLog
import WatchConnectivity
import JanjanCore

/// 워치에서 올라온 기록을 받는 쪽.
///
/// 데이터의 주인은 폰이다(설계 10절). 워치는 사건만 던지고, 저장·재고 계산은 전부 여기서 한다.
/// 워치가 없거나 페어링되지 않아도 앱은 완전히 동작해야 하므로 모든 경로가 조용히 실패한다.
@MainActor
final class PhoneSessionManager: NSObject {

    static let shared = PhoneSessionManager()

    private let logger = Logger(subsystem: Janjan.appBundleID, category: "connectivity")

    weak var doseLogger: (any DoseLogging)?

    /// 워치에 보낼 오늘 요약. 저장소를 읽어야 만들 수 있어 MainActor 로 못박는다.
    var snapshotProvider: (@MainActor () -> WatchSnapshot)?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            logger.info("이 기기는 WatchConnectivity 를 지원하지 않습니다.")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// 오늘 요약을 워치로 밀어 넣는다. 실패해도 워치가 다음에 열릴 때 다시 요청한다.
    func pushSnapshot(_ snapshot: WatchSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        do {
            let data = try JSONEncoder().encode(snapshot)
            try session.updateApplicationContext([WatchMessage.Key.snapshot: data])
        } catch {
            logger.error("워치 스냅샷 전송 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    fileprivate func handle(_ message: WatchMessage) {
        switch message {
        case .doseAction(let medicationIDs, let slotKey, let action):
            doseLogger?.logDose(
                medicationIDs: medicationIDs,
                slotKey: slotKey,
                action: action,
                source: .watch,
                at: Date()
            )
        case .symptom(let symptomID, let severity, let date):
            doseLogger?.logSymptom(
                symptomID: symptomID,
                severity: severity,
                at: date,
                source: .watch
            )
        case .mood(let score, let date):
            doseLogger?.logMood(score: score, at: date)
        case .requestSnapshot:
            if let snapshot = snapshotProvider?() {
                pushSnapshot(snapshot)
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension PhoneSessionManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let state = activationState.rawValue
        Task { @MainActor in
            PhoneSessionManager.shared.logger.info("WCSession 활성화 상태 \(state, privacy: .public)")
        }
    }

    /// iOS 전용 필수 메서드. 사용자가 다른 워치로 갈아탈 때 불린다.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // 새 워치로 다시 붙는다.
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let parsed = WatchMessage(payload: message) else { return }
        Task { @MainActor in
            PhoneSessionManager.shared.handle(parsed)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        guard let parsed = WatchMessage(payload: userInfo) else { return }
        Task { @MainActor in
            PhoneSessionManager.shared.handle(parsed)
        }
    }
}
