import Combine
import Foundation
import UIKit

/// 자정을 넘기는 순간을 알아채는 시계 (QA 2026-09-19).
///
/// **왜 필요한가.** 화면들이 `Date()` 를 그때그때 읽었다. 순수 함수 호출이라
/// SwiftUI 에게는 아무 변화가 아니어서, 앱을 켜 둔 채 자정을 넘기면 화면이
/// 어제에 멈춰 있었다 - 인사말도, 오늘의 시간대도, 다음 진료 D- 도.
/// 자기 전에 오늘 화면을 열어 두고 자정을 넘긴 사람이 정확히 이것을 본다.
///
/// 앱이 앞으로 나올 때만 날짜를 새로 읽는 구조라 백그라운드에 한 번도
/// 안 내린 사람에게는 영영 갱신되지 않았고, 미기록 채우기와 Pro 만료
/// 확인도 같은 문에 걸려 함께 늦었다.
///
/// 하나의 값을 모두가 보게 한다. 환경에 꽂지 않고 공유 인스턴스를 쓰는
/// 이유는 미리보기와 시트에서도 따로 손대지 않고 같은 값을 보게 하기 위해서다.
@MainActor
final class JanjanClock: ObservableObject {

    static let shared = JanjanClock()

    /// 지금 화면이 "오늘" 로 삼는 날. 자정에 한 번 바뀐다.
    ///
    /// **시각까지 든 값이다.** 앱을 켠 그 순간이지 자정이 아니다. 그래서
    /// "오늘 안에 있는가" 를 `<= today` 로 물으면 안 된다 - 오전에 켜 둔 앱에서
    /// 오후에 적은 기록이 미래로 판정돼 목록에서 사라진다(QA 2026-09-21).
    /// 그럴 때는 `endOfToday` 와 비교한다.
    @Published private(set) var today: Date = Date()

    /// 오늘이 끝나는 순간(오늘 23:59:59). `< endOfToday` 가 "오늘까지" 다.
    ///
    /// **내일 0시가 아니다**(2026-09-21 수정). 이 값을 받는 쪽들은 "오늘 안의
    /// 어떤 순간" 으로 보고 `startOfDay` 를 다시 건다. 내일 0시를 주면 그
    /// startOfDay 가 내일이라 하루가 통째로 밀렸다 - 복약률의 경과일이 하루 더
    /// 세어져 꼬박 먹은 사람이 95% 로 내려갔고, 진료를 적자마자 "복약률 0%" 가
    /// 떴으며(진료 당일 가드가 무력해졌다), 종이 머리글의 기간이 아직 오지 않은
    /// 날로 끝났다(QA 2026-09-21).
    var endOfToday: Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        return calendar.date(byAdding: .day, value: 1, to: start)?
            .addingTimeInterval(-1) ?? today
    }

    private var observers: [NSObjectProtocol] = []

    private init() {
        // 자정, 시간대 변경·서머타임 같은 큰 시각 변화, 그리고 앞으로 나올 때.
        // 셋 다 들어야 한다 - 자정 알림은 기기가 잠들어 있으면 늦게 오기도 한다.
        let names: [Notification.Name] = [
            .NSCalendarDayChanged,
            UIApplication.significantTimeChangeNotification,
            UIApplication.willEnterForegroundNotification
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in JanjanClock.shared.tick() }
            }
        }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    /// 날이 실제로 바뀌었을 때만 값을 갈아 끼운다. 같은 날이면 화면을 다시
    /// 그리게 하지 않는다 - 앞으로 나올 때마다 전부 다시 그리면 그것대로 낭비다.
    private func tick() {
        let now = Date()
        guard !Calendar.current.isDate(now, inSameDayAs: today) else { return }
        today = now
    }
}
