import SwiftUI
import JanjanCore

// 설계 02절의 형태 규칙을 컴포넌트로 굳혀 둔다.
// 카드 24pt · 큰 타일 28pt · 칩과 버튼은 완전한 알약 · 화면당 검은 원 버튼 하나.

/// 연회색 바탕 위의 순백 카드.
struct JanjanCard<Content: View>: View {

    /// 카드 안쪽 여백.
    ///
    /// 바깥 여백 16 과 더해 글자가 화면 끝에서 32pt 에서 시작한다 — 애플의 기본
    /// 그룹 목록과 같은 값이다. 예전에는 20 이라 36pt 였고, 393pt 화면에서 글자가
    /// 쓸 수 있는 폭이 321pt 뿐이었다. 카드가 겹겹이 쌓인 화면에서 그만큼
    /// 좁아 보였다.
    var padding: CGFloat = CGFloat(JanjanSpacing.m)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.card), style: .continuous)
                    .fill(Color.surface)
            )
    }
}

/// 파스텔 타일. 시간대·구역을 나눌 때.
struct JanjanTile<Content: View>: View {

    let tint: JanjanColor
    var padding: CGFloat = CGFloat(JanjanSpacing.m)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.tile), style: .continuous)
                    .fill(Color.janjan(tint))
            )
    }
}

/// 알약 칩. 용량·상태·감정 단어에 두루 쓴다.
/// 색만으로 상태를 말하지 않으므로 항상 글자가 함께 들어간다.
struct PillChip: View {

    let text: String
    var tint: JanjanColor = .surface2
    var textTint: JanjanColor = .ink2

    var body: some View {
        Text(text)
            .janjanBody(13, weight: .medium)
            .foregroundStyle(Color.janjan(textTint))
            .padding(.horizontal, CGFloat(JanjanSpacing.s))
            .padding(.vertical, CGFloat(JanjanSpacing.xxs) + 2)
            .background(Capsule(style: .continuous).fill(Color.janjan(tint)))
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// 기분 색 일곱 개 한 줄. 화면 폭을 고르게 나눠 갖는다.
///
/// 처음에는 고정 44pt 일곱 개였다. 간격까지 356pt 인데 카드·바깥 여백을 더하면
/// 420pt - 어느 아이폰에도 다 들어가지 않아서, 이 줄이 있는 화면(오늘·기록)만
/// 통째로 넘쳐 좌우가 잘렸다. 402pt 기기에서는 여백이 이상하게 좁아 보이는
/// 정도였지만 SE(375pt)에서는 제목 글자까지 잘렸다. 요일 알약과 같은 병이라
/// 같은 약을 쓴다: 최소 폭을 곱해 늘어놓지 않고, 주어진 폭을 나눈다.
struct MoodPickerRow: View {

    let chosenScore: Int?
    let pick: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(JanjanMood.scores, id: \.self) { score in
                dot(score)
            }
        }
    }

    private func dot(_ score: Int) -> some View {
        let isChosen = chosenScore == score
        return Button {
            pick(score)
        } label: {
            Circle()
                .fill(Color.mood(score))
                .overlay {
                    // 고른 것을 색이 아니라 테두리로도 말한다.
                    Circle()
                        .strokeBorder(Color.ink, lineWidth: isChosen ? 2 : 0)
                        .padding(-3)
                }
                .frame(maxWidth: 38, maxHeight: 38)
                // 칸 전체가 눌린다. 동그라미가 줄어도 손가락 자리는 그대로다.
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(JanjanMood.label(forScore: score)))
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : [.isButton])
    }
}

/// 나머지 버튼은 전부 흰 알약.
struct WhitePillButton: View {

    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .regular))
                }
                Text(title)
                    .janjanBody(15, weight: .medium)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, CGFloat(JanjanSpacing.m))
            .padding(.vertical, CGFloat(JanjanSpacing.s))
            .background(Capsule(style: .continuous).fill(Color.surface))
        }
        .buttonStyle(.plain)
    }
}

/// 화면 폭을 다 쓰는 검은 알약 버튼. 검은 원 버튼과 같은 자리(화면당 하나)를 차지하므로,
/// 결제처럼 되돌릴 수 없는 결정 하나에만 쓴다.
struct BlackPillButton: View {

    let title: String
    var isBusy: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView()
                        .tint(Color.janjan(.surface))
                } else {
                    Text(title)
                        .janjanBody(17, weight: .semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundStyle(Color.janjan(.surface))
            .background(
                Capsule(style: .continuous)
                    .fill(Color.janjan(.ink).opacity(isEnabled ? 1 : 0.35))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
    }
}

/// 지름 36pt 흰 원 안의 선 아이콘. 색 아이콘은 쓰지 않는다.
struct CircleGlyph: View {

    let systemImage: String
    var background: JanjanColor = .surface
    var foreground: JanjanColor = .ink2
    var diameter: CGFloat = 36

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: diameter * 0.42, weight: .light))
            .foregroundStyle(Color.janjan(foreground))
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(Color.janjan(background)))
    }
}

/// 화면 전체에 깔리는 안개색 바탕.
struct FogBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.fog.ignoresSafeArea())
    }
}

extension View {
    func fogBackground() -> some View { modifier(FogBackground()) }
}

/// 어느 화면에서든 같은 문장으로 나가는 면책 한 줄.
struct MedicalDisclaimer: View {
    var body: some View {
        Text(Janjan.medicalDisclaimerKo)
            .janjanBody(12)
            .foregroundStyle(Color.muted)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 흰 카드 안에 들어가는 한 줄 입력칸.
/// 테두리를 그리지 않고 라벨과 여백으로만 나눈다 — 화면에 선을 늘리지 않기 위해서다.
struct JanjanField: View {

    let label: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
            Text(label)
                .janjanBody(12, weight: .medium)
                .foregroundStyle(Color.muted)
            TextField(placeholder, text: $text)
                .janjanBody(16)
                .foregroundStyle(Color.ink)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 눌러서 켜고 끄는 알약. 요일·시간대처럼 여러 개를 고를 때.
/// 켜지면 바탕과 글자가 함께 뒤집힌다. 색맹·저시력에서도 명도 차이로 구별된다.
struct TogglePill: View {

    let text: String
    let isOn: Bool

    /// 글자가 짧아도 누를 만한 넓이를 지키는 최소 폭.
    ///
    /// 요일처럼 한 글자짜리를 일곱 개 늘어놓을 때는 이 40 이 그대로 곱해져
    /// 줄이 화면 밖으로 나간다. 그럴 때는 0 으로 두고 `fillsRow` 를 쓴다.
    var minWidth: CGFloat = 40

    /// 줄에서 남는 폭을 고르게 나눠 가진다.
    ///
    /// 최소 폭을 곱해 늘어놓는 대신 화면이 주는 만큼만 쓴다. 그래서 기기가
    /// 좁아져도 넘치지 않는다 — 넘치면 가운데 정렬된 바깥 VStack 이 그 폭까지
    /// 커져서, 이 줄뿐 아니라 **화면의 모든 카드**가 좌우로 잘려 나간다.
    var fillsRow: Bool = false

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .janjanBody(14, weight: .medium)
                .foregroundStyle(Color.janjan(isOn ? .surface : .ink2))
                .frame(minWidth: minWidth)
                .padding(.horizontal, CGFloat(fillsRow ? JanjanSpacing.xs : JanjanSpacing.s))
                .padding(.vertical, CGFloat(JanjanSpacing.xs))
                .frame(maxWidth: fillsRow ? .infinity : nil)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.janjan(isOn ? .ink : .surface2))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : [.isButton])
    }
}

/// 숫자를 하나씩 올리고 내리는 줄.
///
/// 시스템 `Stepper` 는 회색 시스템 컨트롤이라 "칩과 버튼은 완전한 알약" 규칙(설계 02절)과
/// 어긋난다. 개수·세기·시간처럼 눈금이 있는 값은 전부 이걸 쓴다.
struct CountStepper: View {

    let text: String
    var decreaseLabelKo: String = "줄이기"
    var increaseLabelKo: String = "늘리기"
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        HStack(spacing: CGFloat(JanjanSpacing.s)) {
            button("minus", label: decreaseLabelKo, action: onDecrease)

            Text(text)
                .janjanBody(14)
                .foregroundStyle(Color.ink2)
                .monospacedDigit()

            button("plus", label: increaseLabelKo, action: onIncrease)

            Spacer(minLength: 0)
        }
    }

    private func button(
        _ systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            CircleGlyph(systemImage: systemImage, background: .surface2, diameter: 30)
                // 동그라미는 30pt 그대로 두고 누를 수 있는 범위만 44pt 로 넓힌다.
                // 애플이 정한 최소 크기이고, 손이 떨리는 날에도 눌러야 하는 버튼이다.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
