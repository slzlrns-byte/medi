import Foundation

// design/tokens.json (v0.6.0) 을 Swift 로 옮긴 것.
//
// SwiftUI 를 import 하지 않는다. 순수 값이라 macOS 러너에서 그대로 테스트할 수 있고,
// 앱 계층에서 Color / UIColor 로 감싸 쓴다.
// 값을 고칠 때는 design/tokens.json 과 여기를 함께 고친다.

/// 라이트/다크 두 벌.
public enum JanjanColorScheme: String, Sendable, CaseIterable {
    case light
    case dark
}

/// 팔레트 토큰. 진한 색은 글자·점·검은 버튼뿐이고 면은 전부 파스텔이거나 흰색이다.
public enum JanjanColor: String, Sendable, CaseIterable {

    // 바탕과 면
    /// 바탕. tokens.json 에서는 `paper` 라는 이름을 쓴다.
    case fog
    case surface
    case surface2

    // 글자
    case ink
    case ink2
    case muted

    // 선
    case line
    case line2

    // 파스텔
    case sage
    case sageInk
    case lav
    case lavInk
    case butter
    case butterInk
    case peach
    case peachInk

    // 기분 7단계 (−3 → +3)
    case mood1
    case mood2
    case mood3
    case mood4
    case mood5
    case mood6
    case mood7

    /// design/tokens.json 에서의 키 이름.
    public var tokenKey: String {
        switch self {
        case .fog: return "paper"
        case .surface: return "surface"
        case .surface2: return "surface2"
        case .ink: return "ink"
        case .ink2: return "ink2"
        case .muted: return "muted"
        case .line: return "line"
        case .line2: return "line2"
        case .sage: return "sage"
        case .sageInk: return "sage-ink"
        case .lav: return "lav"
        case .lavInk: return "lav-ink"
        case .butter: return "butter"
        case .butterInk: return "butter-ink"
        case .peach: return "peach"
        case .peachInk: return "peach-ink"
        case .mood1: return "m1"
        case .mood2: return "m2"
        case .mood3: return "m3"
        case .mood4: return "m4"
        case .mood5: return "m5"
        case .mood6: return "m6"
        case .mood7: return "m7"
        }
    }

    public var lightHex: String {
        switch self {
        case .fog: return "#F2F2F0"
        case .surface: return "#FFFFFF"
        case .surface2: return "#E9EAE7"
        case .ink: return "#1C1C1B"
        case .ink2: return "#4E4F4B"
        case .muted: return "#8B8C87"
        case .line: return "#E4E5E1"
        case .line2: return "#D2D3CF"
        case .sage: return "#CBDAD5"
        case .sageInk: return "#3E5F58"
        case .lav: return "#DDD9F2"
        case .lavInk: return "#4F4A7A"
        case .butter: return "#F1EEA9"
        case .butterInk: return "#6E6A1E"
        case .peach: return "#F4E1D6"
        case .peachInk: return "#8A5A45"
        case .mood1: return "#A29BCB"
        case .mood2: return "#B9B4D9"
        case .mood3: return "#D0CDE3"
        case .mood4: return "#DADAD6"
        case .mood5: return "#C4D8D0"
        case .mood6: return "#A6C7BB"
        case .mood7: return "#7FAF9F"
        }
    }

    public var darkHex: String {
        switch self {
        case .fog: return "#161716"
        case .surface: return "#1F201E"
        case .surface2: return "#272826"
        case .ink: return "#ECECE9"
        case .ink2: return "#C6C7C2"
        case .muted: return "#8E8F8A"
        case .line: return "#2E2F2C"
        case .line2: return "#3B3C39"
        case .sage: return "#2C3B37"
        case .sageInk: return "#A9CFC3"
        case .lav: return "#2E2B45"
        case .lavInk: return "#C4BDEF"
        case .butter: return "#3A3820"
        case .butterInk: return "#E4DF8C"
        case .peach: return "#3E2E27"
        case .peachInk: return "#E8B9A3"
        case .mood1: return "#6F68A0"
        case .mood2: return "#7F79AA"
        case .mood3: return "#8F8BAE"
        case .mood4: return "#8E8F8A"
        case .mood5: return "#7E9C90"
        case .mood6: return "#79AC96"
        case .mood7: return "#7FBBA3"
        }
    }

    public func hex(for scheme: JanjanColorScheme) -> String {
        scheme == .dark ? darkHex : lightHex
    }

    public func rgb(for scheme: JanjanColorScheme) -> JanjanRGB {
        // 위의 값은 전부 손으로 확인한 6자리 hex 라 파싱이 실패할 수 없지만,
        // 그래도 강제 언래핑은 쓰지 않는다.
        JanjanRGB(hex: hex(for: scheme)) ?? JanjanRGB(red: 0, green: 0, blue: 0)
    }
}

/// 0…1 로 정규화된 색. 앱 계층에서 Color / UIColor 로 감쌀 때 쓴다.
public struct JanjanRGB: Hashable, Sendable {

    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// "#RRGGBB" 또는 "RRGGBB" 또는 "#RRGGBBAA" 를 받는다. 그 밖의 형식이면 nil.
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8,
              text.allSatisfy({ $0.isHexDigit }),
              let value = UInt32(text, radix: 16)
        else { return nil }

        if text.count == 6 {
            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255,
                alpha: 1
            )
        } else {
            self.init(
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                alpha: Double(value & 0xFF) / 255
            )
        }
    }
}

/// 모서리 반지름. 카드 24 · 큰 타일 28 · 칩과 버튼은 완전한 알약.
public enum JanjanRadius {
    public static let card: Double = 24
    public static let tile: Double = 28
    public static let pill: Double = 999
    public static let row: Double = 18
}

/// 4의 배수 간격.
public enum JanjanSpacing {
    public static let xxs: Double = 4
    public static let xs: Double = 8
    public static let s: Double = 12
    public static let m: Double = 16
    public static let l: Double = 20
    public static let xl: Double = 24
    public static let xxl: Double = 32

    public static let all: [Double] = [xxs, xs, s, m, l, xl, xxl]
}

/// 번들 서체의 PostScript 이름. 오타가 나면 조용히 시스템 서체로 떨어지므로
/// 문자열을 화면 코드에 흩뿌리지 않고 여기 한 곳에만 둔다.
public enum JanjanFontName {
    public static let displayLight = "SUIT-Light"
    public static let displayRegular = "SUIT-Regular"
    public static let bodyLight = "Pretendard-Light"
    public static let bodyRegular = "Pretendard-Regular"
    public static let bodyMedium = "Pretendard-Medium"
    public static let bodySemiBold = "Pretendard-SemiBold"

    /// UIAppFonts 에 적어 둔 파일명. project.yml 과 반드시 같아야 한다.
    public static let bundledFiles = [
        "SUIT-Light.otf",
        "SUIT-Regular.otf",
        "Pretendard-Light.otf",
        "Pretendard-Regular.otf",
        "Pretendard-Medium.otf",
        "Pretendard-SemiBold.otf"
    ]
}

/// 기분 7단계의 색과 라벨. 색만으로 상태를 말하지 않으므로 항상 라벨과 짝지어 쓴다.
/// 자간과 행간 (설계 02절 타이포).
///
/// 한글은 라틴 문자보다 글자폭이 고르고 속공간이 넓어서, 라틴 기준 그대로 두면
/// **큰 제목은 자간이 벌어져 보이고 본문은 행간이 좁아 답답하다.** 크기마다 손으로
/// 값을 적으면 화면마다 어긋나므로 규칙을 한 곳에 두고 테스트로 잠근다.
public enum JanjanTypography {

    public enum Role: Sendable {
        /// 제목·큰 숫자(SUIT Light).
        case display
        /// 본문·UI(Pretendard).
        case body
    }

    /// 자간. 큰 글자일수록 좁히고, 아주 작은 글자는 오히려 살짝 벌린다.
    ///
    /// 작은 글자를 벌리는 이유: 12pt 아래에서 한글 자소가 서로 붙어 보이기 시작한다.
    public static func tracking(forSize size: Double) -> Double {
        switch size {
        case 28...: return -0.6
        case 22..<28: return -0.4
        case 18..<22: return -0.2
        case 14..<18: return 0
        default: return 0.1
        }
    }

    /// 줄 사이에 **더** 넣는 여백. SwiftUI 의 `lineSpacing` 은 기본 행간에 더해지는 값이다.
    ///
    /// 본문은 넉넉하게(대략 1.6줄), 제목은 조금만 — 제목을 본문만큼 벌리면
    /// 한 덩어리로 읽히지 않고 줄이 흩어진다.
    public static func lineSpacing(forSize size: Double, role: Role) -> Double {
        switch role {
        case .display: return (size * 0.18).rounded()
        case .body: return (size * 0.42).rounded()
        }
    }
}

public enum JanjanMood {

    public static let scores: [Int] = [-3, -2, -1, 0, 1, 2, 3]

    public static let labelsKo: [String] = CheckIn.Mood.labelsKo

    public static let colors: [JanjanColor] = [
        .mood1, .mood2, .mood3, .mood4, .mood5, .mood6, .mood7
    ]

    public static func color(forScore score: Int) -> JanjanColor {
        let clamped = min(max(score, -3), 3)
        return colors[clamped + 3]
    }

    public static func label(forScore score: Int) -> String {
        let clamped = min(max(score, -3), 3)
        return labelsKo[clamped + 3]
    }
}

/// 역할별 별칭. 색을 고를 때 "peach" 가 아니라 "건너뜀" 이라고 부를 수 있게.
public enum JanjanSemanticColor {
    public static let taken = JanjanColor.sage
    public static let takenInk = JanjanColor.sageInk
    public static let skipped = JanjanColor.peach
    public static let skippedInk = JanjanColor.peachInk
    public static let night = JanjanColor.lav
    public static let nightInk = JanjanColor.lavInk
    public static let morning = JanjanColor.butter
    public static let morningInk = JanjanColor.butterInk
    public static let actionButton = JanjanColor.ink
}
