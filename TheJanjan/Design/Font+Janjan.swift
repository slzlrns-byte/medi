import SwiftUI
import UIKit
import JanjanCore

/// 번들 서체 래퍼.
///
/// 제목·큰 숫자는 SUIT Light, 본문은 Pretendard. 둘 다 SIL OFL 1.1 이라 번들해도 된다.
/// 서체 파일이 어떤 이유로든 빠지면 조용히 시스템 서체로 떨어진다 — 화면이 깨지느니
/// 덜 예쁜 편이 낫다.
enum JanjanFont {

    /// 실제로 등록된 서체인지 한 번만 확인하고 캐시한다.
    private static let availableNames: Set<String> = {
        var found: Set<String> = []
        for name in [
            JanjanFontName.displayLight,
            JanjanFontName.displayRegular,
            JanjanFontName.bodyLight,
            JanjanFontName.bodyRegular,
            JanjanFontName.bodyMedium,
            JanjanFontName.bodySemiBold
        ] where UIFont(name: name, size: 12) != nil {
            found.insert(name)
        }
        return found
    }()

    static var bundledFontsAreAvailable: Bool { !availableNames.isEmpty }

    /// 제목·큰 숫자. 얇고 크게.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        if availableNames.contains(JanjanFontName.displayLight) {
            return .custom(JanjanFontName.displayLight, size: size, relativeTo: style)
        }
        return .system(size: size, weight: .light, design: .default)
    }

    /// 굵게 강조해야 하는 제목. 설계상 자주 쓰지 않는다.
    static func displayStrong(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        if availableNames.contains(JanjanFontName.displayRegular) {
            return .custom(JanjanFontName.displayRegular, size: size, relativeTo: style)
        }
        return .system(size: size, weight: .regular, design: .default)
    }

    enum BodyWeight {
        case light
        case regular
        case medium
        case semibold

        var postScriptName: String {
            switch self {
            case .light: return JanjanFontName.bodyLight
            case .regular: return JanjanFontName.bodyRegular
            case .medium: return JanjanFontName.bodyMedium
            case .semibold: return JanjanFontName.bodySemiBold
            }
        }

        var systemWeight: Font.Weight {
            switch self {
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            }
        }
    }

    /// 본문·UI.
    static func body(
        _ size: CGFloat,
        weight: BodyWeight = .regular,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        if availableNames.contains(weight.postScriptName) {
            return .custom(weight.postScriptName, size: size, relativeTo: style)
        }
        return .system(size: size, weight: weight.systemWeight, design: .default)
    }
}
