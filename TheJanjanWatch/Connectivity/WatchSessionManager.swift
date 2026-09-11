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

    #if DEBUG
    /// 화면을 찍기 위해 스냅샷을 직접 넣는다. `WatchDemoSeed` 만 부른다.
    /// 시뮬레이터에는 짝지어진 아이폰이 없어 그냥 두면 placeholder 만 보인다.
    @MainActor
    func applyDemoSnapshot(_ snapshot: WatchSnapshot) {
        self.snapshot = snapshot
    }
    #endif

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// 활성화가 끝나기 전에 눌린 전송. 미활성 세션에 보내면 WCSession 이
    /// 에러를 내므로, 잠깐 들고 있다가 활성화 콜백에서 흘려보낸다.
    private var pendingPayloads: [(payload: [String: Any], isRecord: Bool)] = []

    /// 폰에 사건을 보낸다. 닿으면 즉시, 아니면 큐에.
    func send(_ message: WatchMessage) {
        guard WCSession.isSupported() else { return }
        // 큐 표시("아이폰과 만나면 전달돼요")는 기록에만 붙인다.
        // 스냅샷 요청은 기록이 아니고, 폰이 없는 화면 찍기에서도 매번 나간다.
        let isRecord: Bool
        if case .requestSnapshot = message { isRecord = false } else { isRecord = true }
        deliver(message.payload, isRecord: isRecord)
    }

    private func deliver(_ payload: [String: Any], isRecord: Bool) {
        let session = WCSession.default

        guard session.activationState == .activated else {
            onMain { $0.pendingPayloads.append((payload, isRecord)) }
            session.activate()
            return
        }

        guard session.isReachable else {
            queue(payload, isRecord: isRecord)
            return
        }

        if isRecord { setQueuedFlag(false) }
        session.sendMessage(payload, replyHandler: nil) { [weak self] error in
            guard let self else { return }
            self.logger.error("즉시 전송 실패, 큐로 돌립니다: \(error.localizedDescription, privacy: .public)")
            self.queue(payload, isRecord: isRecord)
        }
    }

    /// 방금 보낸 기록을 화면에 먼저 반영한다(낙관적 갱신).
    ///
    /// 폰이 새 스냅샷을 밀어주기 전까지 그 줄이 "미완료" 로 남아 있으면
    /// 사용자가 같은 시간대를 두 번 누르게 된다(QA 2026-09-10). 진짜 스냅샷이
    /// 오면 그대로 덮여서, 폰이 처리하지 못한 경우에도 다시 미완료로 돌아온다.
    func markSlotCompleted(_ slotKey: String) {
        onMain { manager in
            let old = manager.snapshot
            var completedCount = 0
            let slots = old.slots.map { slot -> WatchSnapshot.SlotLine in
                guard slot.slotKey == slotKey, !slot.isCompleted else { return slot }
                completedCount = slot.medicationIDs.isEmpty
                    ? slot.medicationNames.count
                    : slot.medicationIDs.count
                return WatchSnapshot.SlotLine(
                    slotKey: slot.slotKey,
                    labelKo: slot.labelKo,
                    timeText: slot.timeText,
                    medicationNames: slot.medicationNames,
                    medicationIDs: slot.medicationIDs,
                    isCompleted: true
                )
            }
            manager.snapshot = WatchSnapshot(
                generatedAt: old.generatedAt,
                dateText: old.dateText,
                slots: slots,
                remainingCountToday: max(0, old.remainingCountToday - completedCount),
                isPro: old.isPro,
                themeRaw: old.themeRaw
            )
        }
    }

    /// 필요시 약 한 번 복용을 보내고, 화면에 먼저 반영한다(낙관적 갱신).
    ///
    /// `markSlotCompleted` 와 같은 이유다 - 폰의 새 스냅샷이 오기 전까지 방금 누른
    /// 사실이 화면에 없으면 같은 약을 두 번 누르게 된다. 진짜 스냅샷이 오면 덮인다.
    func recordAsNeeded(_ line: WatchSnapshot.AsNeededLine) {
        let now = Date()
        send(.asNeededTaken(medicationID: line.medicationID, quantity: line.quantity, at: now))

        onMain { manager in
            let old = manager.snapshot
            let calendar = Calendar.current
            let timeText = String(
                format: "%02d:%02d",
                calendar.component(.hour, from: now),
                calendar.component(.minute, from: now)
            )
            let asNeeded = old.asNeeded.map { existing -> WatchSnapshot.AsNeededLine in
                guard existing.medicationID == line.medicationID else { return existing }
                return WatchSnapshot.AsNeededLine(
                    medicationID: existing.medicationID,
                    title: existing.title,
                    quantity: existing.quantity,
                    takenTodayTexts: existing.takenTodayTexts + [timeText]
                )
            }
            manager.snapshot = WatchSnapshot(
                generatedAt: old.generatedAt,
                dateText: old.dateText,
                slots: old.slots,
                asNeeded: asNeeded,
                remainingCountToday: old.remainingCountToday,
                isPro: old.isPro,
                themeRaw: old.themeRaw,
                languageRaw: old.languageRaw
            )
        }
    }

    private func queue(_ payload: [String: Any], isRecord: Bool) {
        guard WCSession.isSupported() else { return }
        if isRecord { setQueuedFlag(true) }
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
            // 활성화 전에 눌려 들고 있던 전송부터 흘려보낸다.
            onMain { manager in
                let held = manager.pendingPayloads
                manager.pendingPayloads = []
                for item in held { manager.deliver(item.payload, isRecord: item.isRecord) }
            }
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
