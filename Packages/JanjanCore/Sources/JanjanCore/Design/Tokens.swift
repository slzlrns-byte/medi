import Foundation

// design/tokens.json (v0.7.0) 을 Swift 로 옮긴 것.
//
// SwiftUI 를 import 하지 않는다. 순수 값이라 macOS 러너에서 그대로 테스트할 수 있고,
// 앱 계층에서 Color / UIColor 로 감싸 쓴다.
// 값을 고칠 때는 design/tokens.json 과 여기를 함께 고친다.

/// 라이트/다크 두 벌.
public enum JanjanColorScheme: String, Sendable, CaseIterable {
    case light
    case dark
}

/// 화면의 옷. 셋 중 하나를 설정에서 고른다 (2026-09-10 결정).
///
/// 바탕·카드·글자·선은 세 테마가 똑같이 무채색이다 — 색이 있는 곳은 시간대
/// 타일, 기분 원, 막대 같은 디자인 요소뿐이라, 테마의 차이는 포인트 색뿐이다.
public enum JanjanTheme: String, Sendable, CaseIterable {
    /// 맑은 하늘 — 파랑. 기분은 흐린 보라(힘듦)에서 맑은 파랑(좋음)으로.
    case sky
    /// 풋사과 크림 — 초록. 기존 물결(보라→초록)의 결을 잇는다.
    case sprout
    /// 복숭아 노을 — 살구. 기분은 노을 보라에서 살구빛으로.
    case sunset

    /// 선택을 모르는 곳(워치 기본값·테스트)이 쓰는 값.
    public static let standard: JanjanTheme = .sprout

    public var labelKo: String {
        switch self {
        case .sky: return "맑은 하늘"
        case .sprout: return "풋사과 크림"
        case .sunset: return "복숭아 노을"
        }
    }

    public var labelEn: String {
        switch self {
        case .sky: return "Clear sky"
        case .sprout: return "Apple cream"
        case .sunset: return "Peach dusk"
        }
    }

    public func label(_ language: JanjanLanguage) -> String {
        language == .english ? labelEn : labelKo
    }

    public var detailKo: String {
        switch self {
        case .sky: return "기분이 흐린 보라에서 맑은 파랑으로 흘러요."
        case .sprout: return "기분이 보라에서 풋사과 초록으로 흘러요."
        case .sunset: return "기분이 노을 보라에서 살구빛으로 흘러요."
        }
    }

    public var detailEn: String {
        switch self {
        case .sky: return "Mood flows from hazy violet to clear blue."
        case .sprout: return "Mood flows from violet to fresh green."
        case .sunset: return "Mood flows from dusk violet to apricot."
        }
    }

    public func detail(_ language: JanjanLanguage) -> String {
        language == .english ? detailEn : detailKo
    }
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

    /// 라이트 값. 무채색은 테마와 무관하고, 색은 테마마다 다르다.
    public func lightHex(_ theme: JanjanTheme = .standard) -> String {
        switch self {
        case .fog: return "#F7F7F6"
        case .surface: return "#FFFFFF"
        case .surface2: return "#EEEEEC"
        case .ink: return "#1A1A19"
        case .ink2: return "#4A4B48"
        case .muted: return "#8B8C87"
        case .line: return "#E6E6E4"
        case .line2: return "#D4D4D1"
        case .sage:
            switch theme {
            case .sky: return "#C9DCE4"
            case .sprout: return "#D5E4C9"
            case .sunset: return "#EFD9C2"
            }
        case .sageInk:
            switch theme {
            case .sky: return "#2F5B66"
            case .sprout: return "#55703F"
            case .sunset: return "#8A6238"
            }
        case .lav:
            switch theme {
            case .sky: return "#C5D3EC"
            case .sprout: return "#DCEAE0"
            case .sunset: return "#E8DBEF"
            }
        case .lavInk:
            switch theme {
            case .sky: return "#2F4A72"
            case .sprout: return "#4F7259"
            case .sunset: return "#5F4B82"
            }
        case .butter:
            switch theme {
            case .sky: return "#DBE2EF"
            case .sprout: return "#F7ECD9"
            case .sunset: return "#FFE8CD"
            }
        case .butterInk:
            switch theme {
            case .sky: return "#33587E"
            case .sprout: return "#8A6A2F"
            case .sunset: return "#9A6B2A"
            }
        case .peach:
            switch theme {
            case .sky: return "#E8E2DA"
            case .sprout: return "#F1E4DC"
            case .sunset: return "#F5DCD3"
            }
        case .peachInk:
            switch theme {
            case .sky: return "#6E6254"
            case .sprout: return "#8A5A45"
            case .sunset: return "#8A5A45"
            }
        case .mood1:
            switch theme {
            case .sky: return "#A183C2"
            case .sprout: return "#C0AECB"
            case .sunset: return "#B9A0C9"
            }
        case .mood2:
            switch theme {
            case .sky: return "#BBA4CE"
            case .sprout: return "#D2C5DA"
            case .sunset: return "#CDB8D8"
            }
        case .mood3:
            switch theme {
            case .sky: return "#D4C8DE"
            case .sprout: return "#E2DCD2"
            case .sunset: return "#E4D8E3"
            }
        case .mood4:
            switch theme {
            case .sky: return "#E3E4E6"
            case .sprout: return "#E9E8E3"
            case .sunset: return "#EDEAE4"
            }
        case .mood5:
            switch theme {
            case .sky: return "#BCD7E8"
            case .sprout: return "#D5E4C9"
            case .sunset: return "#F4D9BF"
            }
        case .mood6:
            switch theme {
            case .sky: return "#8FBEDF"
            case .sprout: return "#B7D2A2"
            case .sunset: return "#EFC29B"
            }
        case .mood7:
            switch theme {
            case .sky: return "#4E97D1"
            case .sprout: return "#8FB877"
            case .sunset: return "#E3A272"
            }
        }
    }

    /// 다크 값. 무채색은 기존 다크 그대로, 색은 테마마다 어두운 판을 따로 만들었다.
    public func darkHex(_ theme: JanjanTheme = .standard) -> String {
        switch self {
        case .fog: return "#161716"
        case .surface: return "#1F201E"
        case .surface2: return "#272826"
        case .ink: return "#ECECE9"
        case .ink2: return "#C6C7C2"
        case .muted: return "#8E8F8A"
        case .line: return "#2E2F2C"
        case .line2: return "#3B3C39"
        case .sage:
            switch theme {
            case .sky: return "#21333B"
            case .sprout: return "#2A3524"
            case .sunset: return "#3B3222"
            }
        case .sageInk:
            switch theme {
            case .sky: return "#9CC6D8"
            case .sprout: return "#B4D19E"
            case .sunset: return "#E0C9A0"
            }
        case .lav:
            switch theme {
            case .sky: return "#232C41"
            case .sprout: return "#24332A"
            case .sunset: return "#322B41"
            }
        case .lavInk:
            switch theme {
            case .sky: return "#B4C8EE"
            case .sprout: return "#A8CBB4"
            case .sunset: return "#C4B0E0"
            }
        case .butter:
            switch theme {
            case .sky: return "#26313F"
            case .sprout: return "#362E1E"
            case .sunset: return "#3B2F1E"
            }
        case .butterInk:
            switch theme {
            case .sky: return "#A8C4E8"
            case .sprout: return "#E0C48C"
            case .sunset: return "#E8C48C"
            }
        case .peach:
            switch theme {
            case .sky: return "#33302B"
            case .sprout: return "#382E28"
            case .sunset: return "#3B2B24"
            }
        case .peachInk:
            switch theme {
            case .sky: return "#CBC0AE"
            case .sprout: return "#E0B9A3"
            case .sunset: return "#E8B49B"
            }
        case .mood1:
            switch theme {
            case .sky: return "#8A6BB0"
            case .sprout: return "#937FA8"
            case .sunset: return "#8E77A4"
            }
        case .mood2:
            switch theme {
            case .sky: return "#9A82BC"
            case .sprout: return "#A392B6"
            case .sunset: return "#9E88B2"
            }
        case .mood3:
            switch theme {
            case .sky: return "#9C93AE"
            case .sprout: return "#999489"
            case .sunset: return "#968A92"
            }
        case .mood4: return "#8E8F8A"
        case .mood5:
            switch theme {
            case .sky: return "#6E93B0"
            case .sprout: return "#83A26E"
            case .sunset: return "#AA8A5C"
            }
        case .mood6:
            switch theme {
            case .sky: return "#5A94C4"
            case .sprout: return "#74A85A"
            case .sunset: return "#B28352"
            }
        case .mood7:
            switch theme {
            case .sky: return "#4A88C8"
            case .sprout: return "#62984B"
            case .sunset: return "#BA7846"
            }
        }
    }

    public func hex(for scheme: JanjanColorScheme, theme: JanjanTheme = .standard) -> String {
        scheme == .dark ? darkHex(theme) : lightHex(theme)
    }

    public func rgb(for scheme: JanjanColorScheme, theme: JanjanTheme = .standard) -> JanjanRGB {
        // 위의 값은 전부 손으로 확인한 6자리 hex 라 파싱이 실패할 수 없지만,
        // 그래도 강제 언래핑은 쓰지 않는다.
        JanjanRGB(hex: hex(for: scheme, theme: theme)) ?? JanjanRGB(red: 0, green: 0, blue: 0)
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

    // 설정에서 고를 수 있는 두 번째·세 번째 옷. 전부 OFL 이다.
    public static let plexLight = "IBMPlexSansKR-Light"
    public static let plexRegular = "IBMPlexSansKR-Regular"
    public static let plexMedium = "IBMPlexSansKR-Medium"
    public static let plexSemiBold = "IBMPlexSansKR-SemiBold"
    public static let gowunRegular = "GowunDodum-Regular"

    /// UIAppFonts 에 적어 둔 파일명. project.yml 과 반드시 같아야 한다.
    public static let bundledFiles = [
        "SUIT-Light.otf",
        "SUIT-Regular.otf",
        "Pretendard-Light.otf",
        "Pretendard-Regular.otf",
        "Pretendard-Medium.otf",
        "Pretendard-SemiBold.otf",
        "IBMPlexSansKR-Light.ttf",
        "IBMPlexSansKR-Regular.ttf",
        "IBMPlexSansKR-Medium.ttf",
        "IBMPlexSansKR-SemiBold.ttf",
        "GowunDodum-Regular.ttf"
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
