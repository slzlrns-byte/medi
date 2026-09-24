import SwiftUI
import JanjanCore

/// 테마 하나의 기분 색 일곱 개를 원으로 늘어놓은 견본.
///
/// 이름만으로는 "밤 라일락" 이 어떤 색인지 알 수 없다(사용자 지적 2026-09-22).
/// 페이월의 "Pro 테마" 줄과 설정의 테마 줄이 이것으로 색을 미리 보여 준다.
/// 지금 고른 테마가 아니라 **넘겨받은 테마**의 값을 그린다 - 그래서
/// `Color.janjan` 대신 토큰의 hex 를 직접 읽는다.
struct ThemeSwatch: View {

    let theme: JanjanTheme
    var diameter: CGFloat = 14

    @Environment(\.colorScheme) private var colorScheme

    private var colors: [Color] {
        let scheme: JanjanColorScheme = colorScheme == .dark ? .dark : .light
        let tokens: [JanjanColor] = [.mood1, .mood2, .mood3, .mood4, .mood5, .mood6, .mood7]
        return tokens.map { token in
            Color(uiColor: UIColor(janjanHex: token.hex(for: scheme, theme: theme)) ?? .label)
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: diameter, height: diameter)
            }
        }
        // 색 견본은 장식이다. 이름은 부르는 쪽이 글자로 적는다.
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(JanjanTheme.allCases, id: \.rawValue) { theme in
            HStack {
                ThemeSwatch(theme: theme)
                Text(theme.labelKo)
            }
        }
    }
    .padding()
}
