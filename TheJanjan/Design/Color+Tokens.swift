import SwiftUI
import UIKit
import JanjanCore

// JanjanCore 의 순수 토큰을 SwiftUI Color 로 감싼다.
// 다크 모드는 UIColor 의 동적 제공자로 처리해서, 뷰마다 colorScheme 를 읽지 않아도 된다.

extension UIColor {

    /// "#RRGGBB" 로부터. 형식이 어긋나면 nil — 강제 언래핑하지 않는다.
    convenience init?(janjanHex hex: String) {
        guard let rgb = JanjanRGB(hex: hex) else { return nil }
        self.init(
            red: CGFloat(rgb.red),
            green: CGFloat(rgb.green),
            blue: CGFloat(rgb.blue),
            alpha: CGFloat(rgb.alpha)
        )
    }

    /// 라이트/다크를 함께 들고 있는 동적 색.
    static func janjan(_ token: JanjanColor) -> UIColor {
        UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? token.darkHex : token.lightHex
            return UIColor(janjanHex: hex) ?? UIColor.label
        }
    }
}

extension Color {

    /// 화면 코드에서는 `Color.janjan(.sage)` 한 줄로 쓴다.
    static func janjan(_ token: JanjanColor) -> Color {
        Color(uiColor: .janjan(token))
    }

    // 자주 쓰는 것만 짧은 이름으로.
    static var fog: Color { .janjan(.fog) }
    static var surface: Color { .janjan(.surface) }
    static var ink: Color { .janjan(.ink) }
    static var ink2: Color { .janjan(.ink2) }
    static var muted: Color { .janjan(.muted) }
    static var hairline: Color { .janjan(.line) }

    /// 기분 점수(−3…3)에 대응하는 색. 항상 라벨과 함께 쓴다.
    static func mood(_ score: Int) -> Color {
        .janjan(JanjanMood.color(forScore: score))
    }
}
