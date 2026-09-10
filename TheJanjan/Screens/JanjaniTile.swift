import SwiftUI
import JanjanCore

/// 오늘 탭의 잔잔이 자리.
///
/// 잔잔이는 굶지 않고, 아프지 않고, 떠나지 않는다. 약을 걸러도 이 타일은
/// 아무것도 바뀌지 않는다 — 바뀌는 것은 시간(아침·낮·밤), 물빛(그날 기분 색),
/// 물가에 쌓인 것들(기록한 날 수)뿐이고, 셋 다 벌이 아니다.
///
/// 톡 치면 물장구를 치고, 길게 누르면 한 바퀴 구른다. 그게 전부다 —
/// 보상도 과제도 없다. 그냥 곁에 있다.
struct JanjaniTile: View {

    let moodScore: Int?
    let keepsakes: Int

    @State private var splashTrigger = 0
    @State private var rollTrigger = 0

    /// 화면 찍기에서는 항상 낮이고 움직이지 않는다. 사진이 매번 같아야
    /// 달라진 것만 눈에 띈다.
    private var isScreenshotRun: Bool {
        ProcessInfo.processInfo.arguments.contains("-JanjanSeedDemoData")
    }

    private var phase: JanjaniPhase {
        isScreenshotRun ? .day : JanjaniPhase.phase(at: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            JanjaniScene(
                phase: phase,
                keepsakes: keepsakes,
                isAnimated: !isScreenshotRun,
                splashTrigger: splashTrigger,
                rollTrigger: rollTrigger
            )
            .frame(maxWidth: .infinity)
            .frame(height: 150)

            Text("잔잔이가 곁에 있어요")
                .janjanBody(13)
                .foregroundStyle(phase == .night ? Color(janjanHex: "#9D9AB8") : Color(janjanHex: "#5C7A6F"))
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.bottom, CGFloat(JanjanSpacing.s))
        }
        .background(JanjaniWater.gradient(phase: phase, moodScore: moodScore))
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.tile), style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.tile), style: .continuous))
        .onTapGesture { splashTrigger += 1 }
        .onLongPressGesture(minimumDuration: 0.35) { rollTrigger += 1 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityKo))
    }

    private var accessibilityKo: String {
        switch phase {
        case .morning: return "잔잔이가 물 위에서 헤엄치고 있어요"
        case .day: return "잔잔이가 물 위에 떠 있어요"
        case .night: return "잔잔이가 잠들어 있어요"
        }
    }
}
