#if DEBUG
import Foundation
import JanjanCore

/// 워치 화면을 찍기 위해 예시 스냅샷을 넣고, 열 화면을 고른다.
///
/// **`#if DEBUG` 안에만 있다.** 출시 빌드에서는 컴파일조차 되지 않는다.
///
/// watchOS 는 XCUITest 를 지원하지 않아서 아이폰처럼 눌러 가며 찍을 수 없다.
/// 그래서 `simctl` 로 앱을 띄우되, **어느 화면으로 열지를 실행 인자로 받는다.**
/// 화면마다 앱을 한 번씩 새로 띄워 찍는 셈이다.
enum WatchDemoSeed {

    /// 열고 싶은 화면.
    enum Screen: String {
        case home
        case mood
        case symptom
        /// 아직 답하지 않은 첫 시간대의 복약 시트.
        case dose
    }

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var isRequested: Bool {
        arguments.contains("-JanjanSeedDemoData")
    }

    /// `-JanjanScreen mood` 처럼 받는다. 없으면 홈.
    static var requestedScreen: Screen {
        guard let index = arguments.firstIndex(of: "-JanjanScreen"),
              arguments.indices.contains(index + 1),
              let screen = Screen(rawValue: arguments[index + 1])
        else { return .home }
        return screen
    }

    /// `-JanjanLanguage en` 처럼 받는다. 없으면 한국어(기본).
    static var requestedLanguage: JanjanLanguage {
        guard let index = arguments.firstIndex(of: "-JanjanLanguage"),
              arguments.indices.contains(index + 1),
              let language = JanjanLanguage(rawValue: arguments[index + 1])
        else { return .standard }
        return language
    }

    /// 폰이 없어도 화면이 채워지도록 예시 스냅샷을 넣는다.
    ///
    /// 시뮬레이터에는 짝지어진 아이폰이 없어서 그냥 두면 placeholder 만 보인다.
    /// 빈 화면을 찍어 봐야 아무것도 알 수 없다.
    @MainActor
    static func applyIfRequested(to session: WatchSessionManager) {
        guard isRequested else { return }
        session.applyDemoSnapshot(demoSnapshot(language: requestedLanguage))
    }

    /// `SampleData.watchSnapshot()` 과 같은 예시 약을 쓰되, 슬롯 라벨을 요청한
    /// 언어로 굽고 필요시 줄 하나(로라제팜)를 더한다 - 홈 화면 찍기에 보이도록.
    private static func demoSnapshot(language: JanjanLanguage) -> WatchSnapshot {
        let referenceDate = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("Md")

        let slots: [WatchSnapshot.SlotLine] = [
            WatchSnapshot.SlotLine(
                slotKey: DoseSlot.morning.storageKey,
                labelKo: DoseSlot.morning.label(language),
                timeText: TimeOfDay(hour: 8, minute: 0).description,
                medicationNames: [SampleData.escitalopram.name],
                medicationIDs: [SampleData.escitalopram.id],
                isCompleted: true
            ),
            WatchSnapshot.SlotLine(
                slotKey: DoseSlot.bedtime.storageKey,
                labelKo: DoseSlot.bedtime.label(language),
                timeText: TimeOfDay(hour: 22, minute: 30).description,
                medicationNames: [SampleData.lamotrigine.name, SampleData.quetiapine.name],
                medicationIDs: [SampleData.lamotrigine.id, SampleData.quetiapine.id],
                isCompleted: false
            )
        ]

        let asNeeded: [WatchSnapshot.AsNeededLine] = [
            WatchSnapshot.AsNeededLine(
                medicationID: SampleData.lorazepam.id,
                title: "\(SampleData.lorazepam.name) \(SampleData.lorazepam.strengthText)",
                quantity: 1,
                takenTodayTexts: ["14:19"]
            )
        ]

        return WatchSnapshot(
            generatedAt: referenceDate,
            dateText: formatter.string(from: referenceDate),
            slots: slots,
            asNeeded: asNeeded,
            remainingCountToday: 2,
            languageRaw: language.rawValue
        )
    }
}
#endif
