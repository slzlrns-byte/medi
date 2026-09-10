import SwiftUI
import JanjanCore

/// 잔잔이가 사는 물. 앱 타일과 위젯이 같은 물을 쓴다.
///
/// 이 파일은 앱과 위젯 **양쪽에 컴파일**되므로 앱 전용 디자인 모듈에 기대지
/// 않는다 — 색은 여기서 직접 만든다.
enum JanjaniWater {

    static func gradient(phase: JanjaniPhase, moodScore: Int?) -> LinearGradient {
        let base: [Color]
        switch phase {
        case .morning: base = [Color(janjanHex: "#E9F1EC"), Color(janjanHex: "#D8E6DF")]
        case .day: base = [Color(janjanHex: "#E4EEE9"), Color(janjanHex: "#D3E2DB")]
        case .night: base = [Color(janjanHex: "#2E2B45"), Color(janjanHex: "#232136")]
        }

        // 그날 고른 기분 색이 물빛에 은은하게 비친다. 평가가 아니라 반영이다.
        guard let score = moodScore else {
            return LinearGradient(colors: base, startPoint: .top, endPoint: .bottom)
        }
        let tint = Color(janjanHex: JanjanMood.color(forScore: score).lightHex)
        let strength = phase == .night ? 0.22 : 0.16
        let tinted = base.map { $0.blended(with: tint, amount: strength) }
        return LinearGradient(colors: tinted, startPoint: .top, endPoint: .bottom)
    }
}

/// 잔잔이 본체 — 물 위의 수달과 물가에 쌓인 것들.
///
/// 배경은 그리지 않는다. 담는 쪽(타일·위젯)이 `JanjaniWater` 로 채운다.
struct JanjaniScene: View {

    let phase: JanjaniPhase
    let keepsakes: Int
    var isAnimated: Bool = true
    /// 톡 쳤을 때 1 씩 올라간다. 물장구(물결 퍼짐)로 답한다.
    var splashTrigger: Int = 0
    /// 쓰다듬었을 때 1 씩 올라간다. 한 바퀴 구르는 것으로 답한다.
    var rollTrigger: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBobbing = false
    @State private var rippleScale: CGFloat = 0.4
    @State private var rippleOpacity: Double = 0
    @State private var rollAngle: Double = 0

    private var night: Bool { phase == .night }

    var body: some View {
        ZStack {
            decorations

            // 물장구의 물결. 수달 아래에서 퍼진다.
            Ellipse()
                .strokeBorder(Color(janjanHex: night ? "#4F4A7A" : "#AECBBE"), lineWidth: 2)
                .frame(width: 150, height: 34)
                .scaleEffect(rippleScale)
                .opacity(rippleOpacity)
                .offset(y: 34)

            otter
                .rotationEffect(.degrees(rollAngle))
                .offset(y: isBobbing ? -2.5 : 2.5)

            keepsakeShore
        }
        .onAppear {
            guard isAnimated, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                isBobbing = true
            }
        }
        .onChange(of: splashTrigger) {
            rippleScale = 0.4
            rippleOpacity = 0.9
            withAnimation(.easeOut(duration: 0.9)) {
                rippleScale = 1.35
                rippleOpacity = 0
            }
        }
        .onChange(of: rollTrigger) {
            withAnimation(.spring(duration: 0.9)) {
                rollAngle += 360
            }
        }
    }

    // MARK: - 꾸밈 (시간대별)

    @ViewBuilder
    private var decorations: some View {
        switch phase {
        case .night:
            Circle()
                .fill(Color(janjanHex: "#E9E6F7").opacity(0.9))
                .frame(width: 22, height: 22)
                .offset(x: 118, y: -52)
            ForEach(Array([(-96, -48), (-64, -62), (66, -34)].enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(Color(janjanHex: "#DDD9F2"))
                    .frame(width: 3.4, height: 3.4)
                    .offset(x: CGFloat(point.0), y: CGFloat(point.1))
            }
        case .morning:
            ForEach(Array([(102, -44, 6.5), (118, -28, 4.0)].enumerated()), id: \.offset) { _, s in
                Circle()
                    .fill(Color(janjanHex: "#F1EEA9"))
                    .frame(width: s.2, height: s.2)
                    .offset(x: CGFloat(s.0), y: CGFloat(s.1))
            }
        case .day:
            EmptyView()
        }
    }

    // MARK: - 물가

    /// 기록한 날 수만큼 조약돌·물풀이 놓인다. 숫자는 어디에도 없다.
    /// 자리가 다 차면(12) 그대로 있는다 — 넘치게 쌓는 것도 셈이 되어 버린다.
    private var keepsakeShore: some View {
        let spots: [(x: CGFloat, w: CGFloat)] = [
            (-140, 13), (140, 11), (-118, 9), (118, 10), (-96, 8), (96, 9),
            (-152, 7), (152, 8), (-76, 7), (76, 7), (-128, 6), (128, 6)
        ]
        let shown = min(max(keepsakes, 0), spots.count)
        let pebbleColors = ["#B7C4BD", "#A9BBB1", "#C2CDC6"]
        return ZStack {
            ForEach(0..<shown, id: \.self) { index in
                let spot = spots[index]
                if index % 3 == 2 {
                    // 물풀 한 줄기.
                    PlantStroke()
                        .stroke(
                            Color(janjanHex: "#7FAF9F").opacity(night ? 0.55 : 0.9),
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                        )
                        .frame(width: 10, height: 20)
                        .offset(x: spot.x, y: 54)
                } else {
                    Ellipse()
                        .fill(Color(janjanHex: pebbleColors[index % pebbleColors.count])
                            .opacity(night ? 0.5 : 1))
                        .frame(width: spot.w, height: spot.w * 0.68)
                        .offset(x: spot.x, y: 62)
                }
            }
        }
    }

    // MARK: - 수달

    private var otter: some View {
        Canvas { context, _ in
            let body = Color(janjanHex: "#A9846B")
            let dark = Color(janjanHex: "#96755E")
            let belly = Color(janjanHex: "#D9C3AD")
            let muzzle = Color(janjanHex: "#E9DCCB")
            let line = Color(janjanHex: "#5B4636")
            let eye = Color(janjanHex: "#4A3A2E")

            // 그림자
            context.fill(
                Path(ellipseIn: CGRect(x: 32, y: 102, width: 172, height: 20)),
                with: .color(.black.opacity(night ? 0.18 : 0.07))
            )

            // 꼬리
            var tail = Path()
            tail.move(to: CGPoint(x: 188, y: 92))
            tail.addQuadCurve(to: CGPoint(x: 218, y: 74), control: CGPoint(x: 214, y: 88))
            tail.addQuadCurve(to: CGPoint(x: 206, y: 96), control: CGPoint(x: 221, y: 88))
            tail.addQuadCurve(to: CGPoint(x: 188, y: 94), control: CGPoint(x: 196, y: 101))
            tail.closeSubpath()
            context.fill(tail, with: .color(body))

            // 몸통(배영)과 배
            context.fill(
                Path(roundedRect: CGRect(x: 70, y: 62, width: 126, height: 46), cornerRadius: 23),
                with: .color(body)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: 89, y: 58, width: 88, height: 48)),
                with: .color(belly)
            )

            // 뒷발 둘
            fillRotatedEllipse(&context, center: CGPoint(x: 182, y: 66), size: CGSize(width: 24, height: 16), degrees: -18, color: dark)
            fillRotatedEllipse(&context, center: CGPoint(x: 196, y: 76), size: CGSize(width: 22, height: 15), degrees: -30, color: dark)

            // 배 위의 조약돌과 앞발
            context.fill(
                Path(ellipseIn: CGRect(x: 113, y: 53, width: 40, height: 26)),
                with: .color(Color(janjanHex: "#C9CFC9"))
            )
            fillRotatedEllipse(&context, center: CGPoint(x: 120, y: 70), size: CGSize(width: 18, height: 14), degrees: 18, color: dark)
            fillRotatedEllipse(&context, center: CGPoint(x: 146, y: 70), size: CGSize(width: 18, height: 14), degrees: -18, color: dark)

            // 머리
            context.fill(Path(ellipseIn: CGRect(x: 32, y: 28, width: 68, height: 68)), with: .color(body))

            // 귀
            for x in [42.0, 90.0] {
                context.fill(Path(ellipseIn: CGRect(x: x - 7.5, y: 30.5, width: 15, height: 15)), with: .color(dark))
                context.fill(Path(ellipseIn: CGRect(x: x - 3.6, y: 34.4, width: 7.2, height: 7.2)), with: .color(Color(janjanHex: "#C9A98D")))
            }

            // 주둥이·코·입
            context.fill(Path(ellipseIn: CGRect(x: 46, y: 60, width: 40, height: 28)), with: .color(muzzle))
            var nose = Path()
            nose.move(to: CGPoint(x: 60, y: 70))
            nose.addQuadCurve(to: CGPoint(x: 72, y: 70), control: CGPoint(x: 66, y: 65))
            nose.addQuadCurve(to: CGPoint(x: 66, y: 76), control: CGPoint(x: 70, y: 76))
            nose.addQuadCurve(to: CGPoint(x: 60, y: 70), control: CGPoint(x: 62, y: 76))
            nose.closeSubpath()
            context.fill(nose, with: .color(line))

            var mouth = Path()
            mouth.move(to: CGPoint(x: 66, y: 76))
            mouth.addLine(to: CGPoint(x: 66, y: 81))
            mouth.move(to: CGPoint(x: 66, y: 81))
            mouth.addQuadCurve(to: CGPoint(x: 55, y: 84), control: CGPoint(x: 61, y: 87))
            mouth.move(to: CGPoint(x: 66, y: 81))
            mouth.addQuadCurve(to: CGPoint(x: 77, y: 84), control: CGPoint(x: 71, y: 87))
            context.stroke(mouth, with: .color(line), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // 눈 - 아침에는 뜨고, 낮과 밤에는 감는다.
            if phase == .morning {
                context.fill(Path(ellipseIn: CGRect(x: 48.6, y: 54.6, width: 6.8, height: 6.8)), with: .color(eye))
                context.fill(Path(ellipseIn: CGRect(x: 76.6, y: 54.6, width: 6.8, height: 6.8)), with: .color(eye))
            } else {
                var eyes = Path()
                eyes.move(to: CGPoint(x: 46, y: 58))
                eyes.addQuadCurve(to: CGPoint(x: 58, y: 58), control: CGPoint(x: 52, y: 64))
                eyes.move(to: CGPoint(x: 74, y: 58))
                eyes.addQuadCurve(to: CGPoint(x: 86, y: 58), control: CGPoint(x: 80, y: 64))
                context.stroke(eyes, with: .color(eye), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            }

            // 볼
            for x in [42.0, 90.0] {
                context.fill(
                    Path(ellipseIn: CGRect(x: x - 6, y: 62, width: 12, height: 12)),
                    with: .color(Color(janjanHex: "#E8B29B").opacity(0.55))
                )
            }

            // 잔물결
            var waves = Path()
            for startX in [10.0, 186.0] {
                waves.move(to: CGPoint(x: startX, y: 118))
                waves.addQuadCurve(to: CGPoint(x: startX + 20, y: 118), control: CGPoint(x: startX + 10, y: 112))
                waves.addQuadCurve(to: CGPoint(x: startX + 40, y: 118), control: CGPoint(x: startX + 30, y: 124))
            }
            context.stroke(
                waves,
                with: .color(Color(janjanHex: night ? "#4F4A7A" : "#AECBBE").opacity(0.85)),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
            )
        }
        .frame(width: 230, height: 132)
    }

    private func fillRotatedEllipse(
        _ context: inout GraphicsContext,
        center: CGPoint,
        size: CGSize,
        degrees: Double,
        color: Color
    ) {
        var layer = context
        layer.translateBy(x: center.x, y: center.y)
        layer.rotate(by: .degrees(degrees))
        layer.fill(
            Path(ellipseIn: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)),
            with: .color(color)
        )
    }
}

/// 물풀 한 줄기 - 아래에서 위로 살짝 휘어 오른다.
private struct PlantStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + 3, y: rect.minY),
            control: CGPoint(x: rect.midX - 4, y: rect.midY)
        )
        return path
    }
}

extension Color {

    /// "#RRGGBB" 를 읽는다. 이 파일이 앱 디자인 모듈 없이 서야 해서 여기 둔다.
    init(janjanHex hex: String) {
        var value: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// 두 색을 섞는다. 물빛에 기분 색을 들이는 데 쓴다.
    func blended(with other: Color, amount: Double) -> Color {
        let a = UIColor(self)
        let b = UIColor(other)
        var (r1, g1, b1, o1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, o2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &o1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &o2)
        let t = CGFloat(amount)
        return Color(
            red: Double(r1 + (r2 - r1) * t),
            green: Double(g1 + (g2 - g1) * t),
            blue: Double(b1 + (b2 - b1) * t)
        )
    }
}
