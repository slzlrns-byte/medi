import SwiftData
import SwiftUI
import WidgetKit
import JanjanCore

/// 홈 화면에 사는 잔잔이.
///
/// 위젯은 눌러서 뭘 하는 자리가 아니라 **지금 모습이 보이는 자리**다.
/// 아침엔 헤엄치고, 낮엔 떠 있고, 밤엔 잔다. 그날 고른 기분 색이 물빛에
/// 비치고, 기록한 날 수만큼 물가에 조약돌이 놓인다. 숫자는 없다.
struct JanjaniEntry: TimelineEntry {
    let date: Date
    let phase: JanjaniPhase
    let moodScore: Int?
    let keepsakes: Int

    static let placeholder = JanjaniEntry(date: Date(), phase: .day, moodScore: nil, keepsakes: 5)
}

struct JanjaniProvider: TimelineProvider {

    func placeholder(in context: Context) -> JanjaniEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (JanjaniEntry) -> Void) {
        completion(context.isPreview ? .placeholder : read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JanjaniEntry>) -> Void) {
        let entry = read()
        // 다음 아침·낮·밤 경계에 갈아입는다. 그 사이에는 바뀔 것이 없다.
        completion(Timeline(entries: [entry], policy: .after(nextPhaseBoundary(after: entry.date))))
    }

    /// 하루의 경계는 5시(아침) · 11시(낮) · 19시(밤)다.
    private func nextPhaseBoundary(after now: Date) -> Date {
        let calendar = Calendar.current
        for hour in [5, 11, 19] {
            if let boundary = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now),
               boundary > now {
                return boundary
            }
        }
        let midnight = calendar.startOfDay(for: now.addingTimeInterval(24 * 60 * 60))
        return calendar.date(bySettingHour: 5, minute: 0, second: 0, of: midnight) ?? midnight
    }

    private func read() -> JanjaniEntry {
        let now = Date()
        let container = JanjanModelContainer.make()
        let context = ModelContext(container)

        let checkIns = ((try? context.fetch(FetchDescriptor<CheckInRecord>())) ?? []).map(\.core)
        let doseEvents = ((try? context.fetch(FetchDescriptor<DoseEventRecord>())) ?? []).map(\.core)

        let calendar = Calendar.current
        let todayMood = checkIns
            .filter { calendar.isDateInToday($0.date) }
            .max { $0.updatedAt < $1.updatedAt }?
            .mood.score

        return JanjaniEntry(
            date: now,
            phase: JanjaniPhase.phase(at: now),
            moodScore: todayMood,
            keepsakes: JanjaniKeepsakes.recordedDayCount(
                checkIns: checkIns,
                doseEvents: doseEvents,
                calendar: calendar
            )
        )
    }
}

struct JanjaniWidgetView: View {

    let entry: JanjaniEntry

    var body: some View {
        JanjaniScene(
            phase: entry.phase,
            keepsakes: entry.keepsakes,
            isAnimated: false
        )
        .scaleEffect(0.62)
        .containerBackground(for: .widget) {
            JanjaniWater.gradient(phase: entry.phase, moodScore: entry.moodScore)
        }
    }
}

struct JanjaniWidget: Widget {

    let kind = "JanjaniWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JanjaniProvider()) { entry in
            JanjaniWidgetView(entry: entry)
        }
        .configurationDisplayName("잔잔이")
        .description("잔잔이가 홈 화면에 살아요. 아침엔 헤엄치고 밤엔 잠들어요.")
        .supportedFamilies([.systemSmall])
    }
}
