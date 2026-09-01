import SwiftUI
import UIKit
import JanjanCore

/// 리포트 · "이번 달의 물결".
///
/// 한 달의 기분 색이 한 장의 그림이 된다. 숫자·추세·해석은 붙이지 않는다 —
/// 색만 보여 주면 해석은 본인이 한다. "좋아져야 한다" 는 압박이 생기는 순간
/// 이 카드는 기록을 막는 카드가 된다.
///
/// **내보내는 그림에 약 이름은 없다.** 기분 색과 날짜뿐이라, 올린 사람이 무엇을
/// 먹는지는 그림이 말하지 않는다. 그래서 이 그림만은 바깥에 올려도 안전하다.
struct MonthWaveCard: View {

    let checkIns: [CheckIn]

    /// 보고 있는 달. 지난달로 넘겨 볼 수 있다.
    @State private var shownMonth = Date()
    @State private var exportImage: ExportImage?

    private struct ExportImage: Identifiable {
        let image: UIImage
        let id = UUID()
    }

    private var calendar: Calendar { .current }

    private var wave: MonthWave {
        MonthWave.make(containing: shownMonth, checkIns: checkIns, calendar: calendar)
    }

    private var isShowingCurrentMonth: Bool {
        calendar.isDate(shownMonth, equalTo: Date(), toGranularity: .month)
    }

    var body: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                header
                MonthWaveGrid(wave: wave, today: Date(), calendar: calendar)
                footer
            }
        }
        .sheet(item: $exportImage) { file in
            ShareSheet(items: [file.image])
        }
    }

    private var header: some View {
        HStack(spacing: CGFloat(JanjanSpacing.xs)) {
            Text("이번 달의 물결")
                .janjanDisplay(20)
                .foregroundStyle(Color.ink)
            Spacer(minLength: 0)
            monthButton("chevron.left", labelKo: "지난달") {
                move(by: -1)
            }
            Text("\(String(wave.year))년 \(wave.month)월")
                .janjanBody(14)
                .foregroundStyle(Color.muted)
                .fixedSize()
            monthButton("chevron.right", labelKo: "다음 달") {
                move(by: 1)
            }
            .disabled(isShowingCurrentMonth)
            .opacity(isShowingCurrentMonth ? 0.3 : 1)
        }
    }

    private func monthButton(_ systemImage: String, labelKo: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink2)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(labelKo))
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            Text("기록한 색만 남아요.\n해석은 하지 않아요.")
                .janjanBody(12)
                .foregroundStyle(Color.muted)
            Spacer(minLength: CGFloat(JanjanSpacing.s))
            WhitePillButton(title: "그림으로 저장", systemImage: "square.and.arrow.down") {
                export()
            }
        }
    }

    private func move(by value: Int) {
        if let moved = calendar.date(byAdding: .month, value: value, to: shownMonth) {
            shownMonth = moved
        }
    }

    /// 지금 보고 있는 그대로를 한 장으로 만든다.
    @MainActor
    private func export() {
        let renderer = ImageRenderer(
            content: MonthWaveShareView(wave: wave, today: Date(), calendar: calendar)
                .frame(width: 420)
        )
        renderer.scale = 3
        if let image = renderer.uiImage {
            exportImage = ExportImage(image: image)
        }
    }
}

/// 달력 본체. 화면과 내보내는 그림이 같은 것을 그린다.
///
/// LazyVGrid 를 쓰지 않는다 — ImageRenderer 는 화면 밖에서 그리는데, 게으른
/// 컨테이너는 화면 밖에서 셀을 만들지 않을 수 있다. 줄을 손으로 잘라 그린다.
private struct MonthWaveGrid: View {

    let wave: MonthWave
    let today: Date
    let calendar: Calendar

    private let spacing: CGFloat = 6

    /// 앞뒤 빈 칸을 채워 7칸씩 자른 줄들.
    private var rows: [[MonthWave.DayCell?]] {
        var cells: [MonthWave.DayCell?] = Array(repeating: nil, count: wave.leadingBlanks)
        cells += wave.days.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
    }

    var body: some View {
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                ForEach(["일", "월", "화", "수", "목", "금", "토"], id: \.self) { name in
                    Text(name)
                        .janjanBody(11)
                        .foregroundStyle(Color.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        dayCell(cell)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ cell: MonthWave.DayCell?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if let cell {
                ZStack(alignment: .topTrailing) {
                    if let score = cell.moodScore {
                        shape.fill(Color.mood(score))
                    } else if isFuture(cell.day) {
                        // 아직 오지 않은 날. 아무 말도 하지 않는 옅은 칸.
                        shape.fill(Color.janjan(.surface2).opacity(0.45))
                    } else {
                        // 지나갔는데 기록이 없는 날. 점선일 뿐, 채우라는 재촉이 아니다.
                        shape.strokeBorder(
                            Color.janjan(.line2),
                            style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                        )
                    }
                    Text("\(cell.day)")
                        .janjanBody(10, weight: .medium)
                        .foregroundStyle(numberColor(cell))
                        .padding(5)
                }
                .accessibilityLabel(Text(accessibilityText(cell)))
            } else {
                Color.clear
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private func isFuture(_ day: Int) -> Bool {
        var components = DateComponents()
        components.year = wave.year
        components.month = wave.month
        components.day = day
        guard let date = calendar.date(from: components) else { return false }
        return date > calendar.startOfDay(for: today)
    }

    private func numberColor(_ cell: MonthWave.DayCell) -> Color {
        guard let score = cell.moodScore else { return Color.muted.opacity(0.7) }
        // 짙은 색 위에서는 흰 글자, 옅은 색 위에서는 먹색.
        return abs(score) >= 2 ? Color.janjan(.surface) : Color.ink.opacity(0.55)
    }

    private func accessibilityText(_ cell: MonthWave.DayCell) -> String {
        guard let score = cell.moodScore else { return "\(cell.day)일, 기록 없음" }
        return "\(cell.day)일, \(JanjanMood.label(forScore: score))"
    }
}

/// 내보내는 한 장. 종이색 바탕에 달력과 달 이름, 작은 앱 이름뿐이다.
private struct MonthWaveShareView: View {

    let wave: MonthWave
    let today: Date
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
            HStack(alignment: .lastTextBaseline) {
                Text("이번 달의 물결")
                    .janjanDisplay(24)
                    .foregroundStyle(Color.ink)
                Spacer()
                Text("\(String(wave.year))년 \(wave.month)월")
                    .janjanBody(15)
                    .foregroundStyle(Color.muted)
            }
            MonthWaveGrid(wave: wave, today: today, calendar: calendar)
            HStack {
                Spacer()
                Text("더잔잔")
                    .janjanBody(12, weight: .medium)
                    .foregroundStyle(Color.muted)
            }
        }
        .padding(CGFloat(JanjanSpacing.xl))
        .background(Color.janjan(.fog))
    }
}
