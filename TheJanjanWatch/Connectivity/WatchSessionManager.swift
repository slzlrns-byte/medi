import Foundation
import OSLog
import SwiftUI
import WatchConnectivity
import JanjanCore

/// 워치 ↔ 아이폰 다리.
///
/// 보내는 것: 복약 액션 · 증상 · 기분.
/// 받는 것: 오늘 요약 스냅샷 하나.
/// 폰이 닿지 않으면 `transferUserInfo` 로 큐에 쌓아 두었다가 나중에 전달한다.
///
/// 전역 액터를 붙이지 않는다. WCSessionDelegate 콜백이 임의의 스레드에서 오고
/// SwiftUI 의 `@StateObject` 초기값으로도 쓰이기 때문에, @Published 갱신만
/// 메인 큐로 넘기는 쪽이 단순하고 안전하다.
final class WatchSessionManager: NSObject, ObservableObject {

    static let shared = WatchSessionManager()

    private let logger = Logger(subsystem: Janjan.watchBundleID, category: "connectivity")

    /// 폰이 보내 준 오늘 요약. 아직 못 받았으면 placeholder.
    @Published private(set) var snapshot: WatchSnapshot = .placeholder
    @Published private(set) var isReachable = false
    /// 마지막 전송이 큐에 쌓였는지(폰이 꺼져 있거나 멀리 있음).
    @Published private(set) var lastSendWasQueued = false

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// 폰에 사건을 보낸다. 닿으면 즉시, 아니면 큐에.
    func send(_ message: WatchMessage) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let payload = message.payload

        guard session.isReachable else {
            queue(payload)
            return
        }

        setQueuedFlag(false)
        session.sendMessage(payload, replyHandler: nil) { [weak self] error in
            guard let self else { return }
            self.logger.error("즉시 전송 실패, 큐로 돌립니다: \(error.localizedDescription, privacy: .public)")
            self.queue(payload)
        }
    }

    private func queue(_ payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        setQueuedFlag(true)
        WCSession.default.transferUserInfo(payload)
    }

    func requestSnapshot() {
        send(.requestSnapshot)
    }

    // MARK: - @Published 갱신은 전부 메인 큐에서

    private func setQueuedFlag(_ queued: Bool) {
        onMain { $0.lastSendWasQueued = queued }
    }

    fileprivate func setReachable(_ reachable: Bool) {
        onMain { $0.isReachable = reachable }
    }

    fileprivate func applySnapshot(_ data: Data) {
        do {
            let decoded = try JSONDecoder().decode(WatchSnapshot.self, from: data)
            onMain { $0.snapshot = decoded }
        } catch {
            logger.error("스냅샷 해석 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func onMain(_ work: @escaping (WatchSessionManager) -> Void) {
        if Thread.isMainThread {
            work(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                work(self)
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            logger.error("WCSession 활성화 실패: \(error.localizedDescription, privacy: .public)")
        }
        setReachable(session.isReachable)
        if activationState == .activated {
            requestSnapshot()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        setReachable(session.isReachable)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchMessage.Key.snapshot] as? Data else { return }
        applySnapshot(data)
    }
}
