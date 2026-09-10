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
            JanjanFontName.plexLight,
            JanjanFontName.plexRegular,
            JanjanFontName.plexMedium,
            JanjanFontName.plexSemiBold,
            JanjanFontName.gowunRegular,
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
        let name: String
        switch JanjanFontChoice.current {
        case .standard: name = JanjanFontName.displayLight
        case .plex: name = JanjanFontName.plexLight
        case .gowun: name = JanjanFontName.gowunRegular
        }
        if availableNames.contains(name) {
            return .custom(name, size: size, relativeTo: style)
        }
        return .system(size: size, weight: .light, design: .default)
    }

    /// 굵게 강조해야 하는 제목. 설계상 자주 쓰지 않는다.
    static func displayStrong(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        let name: String
        switch JanjanFontChoice.current {
        case .standard: name = JanjanFontName.displayRegular
        case .plex: name = JanjanFontName.plexMedium
        // 고운돋움은 한 굵기뿐이다. 강조는 크기가 대신한다.
        case .gowun: name = JanjanFontName.gowunRegular
        }
        if availableNames.contains(name) {
            return .custom(name, size: size, relativeTo: style)
        }
        return .system(size: size, weight: .regular, design: .default)
    }

    enum BodyWeight {
        case light
        case regular
        case medium
        case semibold

        var postScriptName: String {
            // 본문을 플렉스로 통째 갈아입는 것은 plex 선택뿐이다.
            // gowun 은 제목만 바꾸고 본문은 프리텐다드를 지킨다 - 한 굵기짜리
            // 서체로 본문 넉 단계 굵기를 흉내 낼 수는 없다.
            let usesPlex = JanjanFontChoice.current == .plex
            switch self {
            case .light: return usesPlex ? JanjanFontName.plexLight : JanjanFontName.bodyLight
            case .regular: return usesPlex ? JanjanFontName.plexRegular : JanjanFontName.bodyRegular
            case .medium: return usesPlex ? JanjanFontName.plexMedium : JanjanFontName.bodyMedium
            case .semibold: return usesPlex ? JanjanFontName.plexSemiBold : JanjanFontName.bodySemiBold
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

// MARK: - 서체 + 자간 + 행간을 한 번에

// 서체만 지정하고 자간·행간을 놓치면 한글이 답답하거나 흩어져 보인다. 셋은 늘 함께
// 가야 하므로 `.font(...)` 를 직접 부르지 않고 아래 두 개만 쓴다.
// 값은 `JanjanTypography` 가 정하고 테스트로 잠겨 있다.

extension View {

    /// 제목·큰 숫자. SUIT Light + 좁힌 자간.
    func janjanDisplay(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> some View {
        font(JanjanFont.display(size, relativeTo: style))
            .tracking(CGFloat(JanjanTypography.tracking(forSize: Double(size))))
            .lineSpacing(CGFloat(JanjanTypography.lineSpacing(forSize: Double(size), role: .display)))
    }

    /// 본문·UI. Pretendard + 한글에 맞춘 행간.
    func janjanBody(
        _ size: CGFloat,
        weight: JanjanFont.BodyWeight = .regular,
        relativeTo style: Font.TextStyle = .body
    ) -> some View {
        font(JanjanFont.body(size, weight: weight, relativeTo: style))
            .tracking(CGFloat(JanjanTypography.tracking(forSize: Double(size))))
            .lineSpacing(CGFloat(JanjanTypography.lineSpacing(forSize: Double(size), role: .body)))
    }
}


/// 설정에서 고르는 서체 옷.
///
/// 셋 다 OFL 이라 번들해도 된다. 기본은 지금까지의 SUIT + 프리텐다드다 -
/// 이미 쓰던 사람의 화면이 어느 날 말없이 바뀌면 안 된다.
enum JanjanFontChoice: String, CaseIterable {

    case standard
    case plex
    case gowun

    static let defaultsKey = "janjan.fontChoice"

    /// 매 호출마다 읽는다. 값이 바뀌면 화면이 다시 그려지며 자연히 새 옷을 입는다.
    static var current: JanjanFontChoice {
        JanjanFontChoice(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .standard
    }

    var labelKo: String {
        switch self {
        case .standard: return "기본"
        case .plex: return "또렷하게"
        case .gowun: return "둥글게"
        }
    }

    var labelEn: String {
        switch self {
        case .standard: return "Default"
        case .plex: return "Crisp"
        case .gowun: return "Rounded"
        }
    }

    func label(_ language: JanjanLanguage) -> String {
        language == .english ? labelEn : labelKo
    }

    var detailKo: String {
        switch self {
        case .standard: return "SUIT 제목과 프리텐다드 본문"
        case .plex: return "IBM Plex Sans KR"
        case .gowun: return "고운돋움 제목과 프리텐다드 본문"
        }
    }

    var detailEn: String {
        switch self {
        case .standard: return "SUIT titles with Pretendard body text"
        case .plex: return "IBM Plex Sans KR"
        case .gowun: return "Gowun Dodum titles with Pretendard body text"
        }
    }

    func detail(_ language: JanjanLanguage) -> String {
        language == .english ? detailEn : detailKo
    }
}
