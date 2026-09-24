import SwiftUI
import JanjanCore

/// 오늘 약을 다 챙긴 순간 한 번 내리는 꽃가루.
///
/// 이 앱에서 축하는 조심스러운 일이다. 복약은 성취가 아니라 매일 하는 일이고,
/// 못 챙긴 날에 벌을 주지 않기로 한 것과 같은 이유로 챙긴 날에 요란을 떨지도
/// 않는다. 그래서 색은 팔레트의 파스텔 넷만 쓰고, 소리도 진동도 없고,
/// 1.6초 안에 끝나고 스스로 사라진다.
///
/// **손짓을 가로막지 않는다.** `allowsHitTesting(false)` 로 얹으므로 꽃가루가
/// 내리는 동안에도 아래 버튼을 그대로 누를 수 있다.
///
/// 동작 줄이기(Reduce Motion)를 켠 사람에게는 아무것도 그리지 않는다 -
/// 화면을 가로질러 떨어지는 것은 그 설정이 줄이려는 바로 그 움직임이다.
struct ConfettiBurst: View {

    /// 몇 조각. 늘릴수록 화려해지지만 이 화면이 말하려는 것과 멀어진다.
    private static let count = 24
    private static let fallDuration: ClosedRange<Double> = 1.1...1.6

    private struct Piece: Identifiable {
        let id = UUID()
        /// 가로 시작 자리(0~1).
        let x: Double
        let delay: Double
        let duration: Double
        /// 떨어지며 옆으로 밀리는 정도.
        let drift: Double
        let spin: Double
        let width: Double
        let height: Double
        let color: JanjanColor
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pieces: [Piece] = []
    @State private var isFalling = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.janjan(piece.color))
                        .frame(width: piece.width, height: piece.height)
                        .rotationEffect(.degrees(isFalling ? piece.spin : 0))
                        .offset(
                            x: proxy.size.width * piece.x
                                + (isFalling ? piece.drift : 0),
                            y: isFalling ? proxy.size.height + 40 : -40
                        )
                        .opacity(isFalling ? 0 : 1)
                        .animation(
                            .easeIn(duration: piece.duration).delay(piece.delay),
                            value: isFalling
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            pieces = Self.make()
            // 한 프레임 뒤에 시작한다. 같은 프레임에서 값을 바꾸면 애니메이션이
            // 붙지 않고 조각이 아래에서 그냥 나타난다.
            DispatchQueue.main.async { isFalling = true }
        }
    }

    private static func make() -> [Piece] {
        let colors: [JanjanColor] = [.sage, .lav, .butter, .peach]
        return (0..<count).map { index in
            Piece(
                x: Double.random(in: 0.02...0.94),
                delay: Double.random(in: 0...0.35),
                duration: Double.random(in: fallDuration),
                drift: Double.random(in: -36...36),
                spin: Double.random(in: -240...240),
                width: Double.random(in: 6...10),
                height: Double.random(in: 10...16),
                color: colors[index % colors.count]
            )
        }
    }
}

#Preview {
    ZStack {
        Color.fog.ignoresSafeArea()
        ConfettiBurst()
    }
}
