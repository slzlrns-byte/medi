import SwiftUI
import JanjanCore

/// 진료 준비 · "패턴 보기" (Pro).
///
/// 최근 4주의 기분·복약·수면을 같은 날짜 눈금에 세 줄로 놓는다.
/// 숫자·상관·해석 문장은 붙이지 않는다 — 세 줄이 나란히 있으면 무엇이
/// 겹치는지는 보는 사람과 진료실이 읽는다(이번 달의 흐름과 같은 원칙).
struct PatternCard: View {

    let timeline: PatternTimeline
    /// 무료 사용자에게는 최근 7일만 선명하고 그 앞은 흐리다.
    /// 잠금 배지와 페이월은 밖의 proGated 가 단다.
    ///
    /// 흐림을 전부에 씌우지 않는 이유(2026-09-19 결정): "이 앱이 나를 안다" 는
    /// 순간을 한 번은 겪어야 잠긴 3주가 궁금해진다. 인사이트를 통째로 벽 뒤에
    /// 두면 그 순간을 경험하기 전에 떠난다는 것이 리서치의 결론이었다.
    let isLocked: Bool
    /// 진료 준비 탭 밖(용량 변경 체크포인트)에서 다른 제목으로 재사용한다.
    var title: String?
    var subtitle: String?

    private let rowHeight: CGFloat = 18
    private let spacing: CGFloat = 2
    /// 무료에게 선명하게 보여 주는 최근 일수.
    static let freeClearDays = 7

    private var lang: JanjanLanguage { .current }

    var body: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(title ?? t("패턴 보기", "Pattern view"))
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)
                Text(subtitle ?? t(
                    "최근 4주의 기분, 복약, 수면을 확인할 수 있어요.",
                    "See mood, doses, and sleep from the past 4 weeks."
                ))
                    .janjanBody(13)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)

                chart

                legend

                if isLocked {
                    Text(t(
                        "최근 7일은 그대로 보여요. 4주 전체는 Pro 에서 열려요.",
                        "The last 7 days stay clear. The full 4 weeks open with Pro."
                    ))
                        .janjanBody(11)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 그림

    /// 이 날짜보다 이전은 흐리게. 무료가 아니면 nil - 아무것도 흐리지 않는다.
    private var blurBefore: Date? {
        guard isLocked, timeline.days.count > Self.freeClearDays else { return nil }
        return timeline.days[timeline.days.count - Self.freeClearDays].date
    }

    private func isBlurred(_ day: PatternTimeline.Day) -> Bool {
        guard let blurBefore else { return false }
        return day.date < blurBefore
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
            chartRow(label: t("기분", "Mood")) { day in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(day.moodScore.map { Color.mood($0) } ?? Color.janjan(.surface2))
                    .frame(height: rowHeight)
            }
            chartRow(label: t("복약", "Doses")) { day in
                doseMark(day.takenFraction)
                    .frame(height: rowHeight)
            }
            chartRow(label: t("수면", "Sleep")) { day in
                sleepMark(day.sleepMinutes)
                    .frame(height: rowHeight + 6, alignment: .bottom)
            }
            axis
        }
    }

    private func chartRow<Mark: View>(
        label: String,
        @ViewBuilder mark: @escaping (PatternTimeline.Day) -> Mark
    ) -> some View {
        HStack(alignment: .center, spacing: CGFloat(JanjanSpacing.xs)) {
            Text(label)
                .janjanBody(11)
                .foregroundStyle(Color.muted)
                .lineLimit(1)
                // 한국어 라벨은 두 글자라 30 이면 되지만 "Doses" 는 넘쳐서
                // "Dose / s" 로 꺾였다(영어 캡처 2026-09-20).
                .frame(width: lang == .english ? 46 : 30, alignment: .leading)
            HStack(spacing: spacing) {
                ForEach(timeline.days, id: \.date) { day in
                    mark(day)
                        // 칸마다 흐린다 - 최근 7일 칸은 잠겨 있어도 선명하다.
                        .blur(radius: isBlurred(day) ? 5 : 0)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// 복약 답의 세 모양. 색만이 아니라 채움/반채움/테두리로 갈린다.
    @ViewBuilder
    private func doseMark(_ fraction: Double?) -> some View {
        let side: CGFloat = 8
        ZStack {
            if let fraction {
                if fraction >= 1 {
                    Circle().fill(Color.ink)
                } else if fraction > 0 {
                    Circle().strokeBorder(Color.ink, lineWidth: 1)
                    Circle()
                        .fill(Color.ink)
                        .mask(alignment: .bottom) {
                            Rectangle().frame(height: side / 2)
                        }
                } else {
                    Circle().strokeBorder(Color.muted, lineWidth: 1)
                }
            }
            // 계획이 없던 날은 빈 칸 - 0% 와 구별한다.
        }
        .frame(width: side, height: side)
    }

    @ViewBuilder
    private func sleepMark(_ minutes: Int?) -> some View {
        if let minutes {
            // 10시간을 꽉 찬 키로 본다. 그 위는 다 같은 키 - 재는 그림이 아니라 결 그림이다.
            let fraction = min(Double(minutes) / (10 * 60), 1)
            Capsule(style: .continuous)
                .fill(Color.janjan(.sage))
                .frame(width: 4, height: max(CGFloat(fraction) * (rowHeight + 6), 3))
        } else {
            Color.clear.frame(width: 4, height: 3)
        }
    }

    /// 처음·가운데·오늘 세 눈금만 적는다. 스물여덟 개를 다 적으면 그림이 죽는다.
    private var axis: some View {
        HStack(spacing: CGFloat(JanjanSpacing.xs)) {
            Color.clear.frame(width: 30, height: 1)
            HStack {
                if let first = timeline.days.first?.date {
                    Text(shortDate(first))
                }
                Spacer(minLength: 0)
                if timeline.days.count > 2 {
                    Text(shortDate(timeline.days[timeline.days.count / 2].date))
                }
                Spacer(minLength: 0)
                Text(t("오늘", "Today"))
            }
            .janjanBody(10)
            .foregroundStyle(Color.muted)
        }
    }

    private var legend: some View {
        Text(t(
            "복약 ● 다 기록 · ◐ 일부 · ○ 기록 없음 · 빈 칸은 계획이 없던 날",
            "Doses: ● all logged · ◐ some · ○ none · blank means nothing was planned"
        ))
            .janjanBody(11)
            .foregroundStyle(Color.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: lang.localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter.string(from: date)
    }
}
