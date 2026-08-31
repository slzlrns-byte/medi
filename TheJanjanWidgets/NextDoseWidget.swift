import AppIntents
import SwiftData
import SwiftUI
import WidgetKit
import JanjanCore

// MARK: - 한 칸에 담을 것

/// 위젯이 그릴 최소한의 것. 저장소를 그대로 들고 다니지 않는다.
struct DoseEntry: TimelineEntry {
    let date: Date

    /// 아직 답하지 않은 가장 이른 시간대. 없으면 오늘 할 일이 끝났거나 약이 없다.
    let slotKey: String?
    let slotLabelKo: String
    let timeText: String
    let medicationNames: [String]
    let pendingCount: Int

    /// 등록한 약이 아예 없는 경우. '다 챙기셨어요' 와 구별해야 한다 —
    /// 아무것도 안 한 사람에게 다 했다고 말하면 안 된다.
    let hasAnyMedication: Bool

    var isDone: Bool { slotKey == nil && hasAnyMedication }

    static let placeholder = DoseEntry(
        date: Date(),
        slotKey: "morning",
        slotLabelKo: "아침",
        timeText: "08:00",
        medicationNames: ["에스시탈로프람"],
        pendingCount: 1,
        hasAnyMedication: true
    )
}

// MARK: - 시간표

struct NextDoseProvider: TimelineProvider {

    func placeholder(in context: Context) -> DoseEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (DoseEntry) -> Void) {
        completion(context.isPreview ? .placeholder : read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DoseEntry>) -> Void) {
        let entry = read()

        // 다음 시간대가 오면 저절로 바뀌어야 한다. 사용자가 앱을 열어 줄 때까지
        // 지난 시간대를 붙들고 있으면 위젯이 거짓말을 하는 셈이다.
        let next = nextRefresh(after: entry.date)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    /// 다음으로 다시 그릴 시각. 오늘 남은 시간대 중 가장 이른 것, 없으면 내일 자정.
    private func nextRefresh(after now: Date) -> Date {
        let calendar = Calendar.current
        let container = JanjanModelContainer.make()
        let context = ModelContext(container)

        let upcoming = TodayPlanReader.slots(on: now, in: context)
            .compactMap { line -> Date? in
                guard !line.isCompleted else { return nil }
                return line.time.date(on: now, calendar: calendar)
            }
            .filter { $0 > now }
            .min()

        let midnight = calendar.startOfDay(for: now.addingTimeInterval(24 * 60 * 60))
        // 최소 15분은 두고 본다. 너무 촘촘하면 시스템이 어차피 미룬다.
        let floor = now.addingTimeInterval(15 * 60)
        return max(min(upcoming ?? midnight, midnight), floor)
    }

    private func read() -> DoseEntry {
        let now = Date()
        let container = JanjanModelContainer.make()
        let context = ModelContext(container)

        let medicationCount = (try? context.fetchCount(FetchDescriptor<MedicationRecord>())) ?? 0
        guard let line = TodayPlanReader.nextPending(on: now, in: context) else {
            return DoseEntry(
                date: now,
                slotKey: nil,
                slotLabelKo: "",
                timeText: "",
                medicationNames: [],
                pendingCount: 0,
                hasAnyMedication: medicationCount > 0
            )
        }

        return DoseEntry(
            date: now,
            slotKey: line.slotKey,
            slotLabelKo: line.slot.labelKo,
            timeText: line.time.description,
            medicationNames: line.medicationNames,
            pendingCount: line.pendingCount,
            hasAnyMedication: true
        )
    }
}

// MARK: - 홈 화면

struct NextDoseWidgetView: View {

    @Environment(\.widgetFamily) private var family
    let entry: DoseEntry

    var body: some View {
        switch family {
        case .systemMedium: mediumBody
        default: smallBody
        }
    }

    // MARK: 작은 칸 — 시간대 하나와 버튼 하나

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let slotKey = entry.slotKey {
                header
                Spacer(minLength: 0)
                takenButton(slotKey: slotKey)
            } else {
                restingBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: 중간 칸 — 약 이름까지 보인다

    private var mediumBody: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if entry.slotKey != nil {
                    header
                    if !entry.medicationNames.isEmpty {
                        Text(entry.medicationNames.joined(separator: " · "))
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else {
                    restingBody
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let slotKey = entry.slotKey {
                takenButton(slotKey: slotKey)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.slotLabelKo)
                    .font(.system(size: 20, weight: .semibold))
                Text(entry.timeText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            // 색만으로 상태를 말하지 않는다. 글자가 항상 함께 온다.
            Text("\(entry.pendingCount)개 남음")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    /// 남은 것이 없을 때. 재촉하지 않고, 하지도 않은 일을 했다고 하지도 않는다.
    private var restingBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.hasAnyMedication ? "오늘 약은 다 챙기셨어요." : "약을 등록하면 여기 나와요.")
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func takenButton(slotKey: String) -> some View {
        Button(intent: LogDoseIntent(slotKey: slotKey)) {
            Text("먹었어요")
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.borderedProminent)
        .tint(.primary)
    }
}

struct NextDoseWidget: Widget {

    let kind = "NextDoseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextDoseProvider()) { entry in
            NextDoseWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("다음 약")
        .description("다음 시간대를 보여 주고, 눌러서 바로 기록해요.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - 잠금화면

/// 잠금화면에는 버튼을 두지 않는다.
///
/// 주머니 안에서 스치기만 해도 먹지 않은 약이 먹은 것으로 적히고 재고까지 깎인다.
/// 되돌릴 수 있다 해도, 되돌려야 할 일을 만들지 않는 편이 낫다.
/// 여기서는 알려 주기만 하고, 누르면 앱이 열린다.
struct NextDoseLockScreenWidget: Widget {

    let kind = "NextDoseLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextDoseProvider()) { entry in
            NextDoseLockScreenView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("다음 약")
        .description("잠금화면에서 다음 시간대를 봐요.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct NextDoseLockScreenView: View {

    @Environment(\.widgetFamily) private var family
    let entry: DoseEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)
        default:
            VStack(alignment: .leading, spacing: 1) {
                if entry.slotKey != nil {
                    Text("\(entry.slotLabelKo) \(entry.timeText)")
                        .font(.headline)
                    Text(entry.medicationNames.isEmpty
                         ? "\(entry.pendingCount)개 남음"
                         : entry.medicationNames.joined(separator: " · "))
                        .font(.caption)
                        .lineLimit(1)
                } else {
                    Text(entry.hasAnyMedication ? "오늘 약은 다 챙기셨어요." : "약을 등록해 주세요.")
                        .font(.caption)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inlineText: String {
        guard entry.slotKey != nil else {
            return entry.hasAnyMedication ? "오늘 약 완료" : "약 등록 전"
        }
        return "\(entry.slotLabelKo) \(entry.timeText) · \(entry.pendingCount)개"
    }
}
