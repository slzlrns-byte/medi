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

    /// 줄이 모자랄 때 줄어들 수 있는지. 기본은 아니다 — 칩은 모양을 지킨다.
    ///
    /// 다만 **길이를 앱이 정하지 않는 글자**(사용자가 지은 약 이름, 영어
    /// 번역문)가 들어가면 얘기가 다르다. 칩이 양보하지 않으므로 줄 전체가
    /// 카드 밖으로 나가고, 넘친 폭이 바깥 VStack 을 키워 그 화면의 카드가
    /// 전부 좌우로 잘린다(QA 2026-09-21 · MoodPickerRow 가 겪은 그 병).
    /// 그런 자리에서만 켠다.
    var truncates: Bool = false

    var body: some View {
        Text(text)
            .janjanBody(13, weight: .medium)
            .foregroundStyle(Color.janjan(textTint))
            .lineLimit(truncates ? 1 : nil)
            .truncationMode(.tail)
            .padding(.horizontal, CGFloat(JanjanSpacing.s))
            .padding(.vertical, CGFloat(JanjanSpacing.xxs) + 2)
            .background(Capsule(style: .continuous).fill(Color.janjan(tint)))
            .fixedSize(horizontal: !truncates, vertical: false)
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
        .accessibilityLabel(Text(CheckIn.Mood(score).label(JanjanLanguage.current)))
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : [.isButton])
    }
}

/// 나머지 버튼은 전부 흰 알약.
///
/// **테두리가 기본이다**(QA 2026-09-19). 알약의 면(surface #FFFFFF)은 흰
/// 카드의 면과 같은 색이라, 카드 안에 놓이면 알약이 통째로 사라지고 글자만
/// 떠 보였다. 다크 모드도 마찬가지다(#1F201E 위 #1F201E). 몇몇 화면은
/// 부르는 자리마다 `.overlay` 로 테두리를 덧대 고쳐 왔는데, 그 방식은 새로
/// 부르는 자리가 생길 때마다 같은 실수를 되풀이하게 한다. 부품이 스스로
/// 경계를 갖게 하고, 정말 필요 없는 자리에서만 `hasBorder: false` 로 뺀다.
struct WhitePillButton: View {

    let title: String
    var systemImage: String?
    /// 포그 배경 위처럼 경계가 이미 보이는 자리에서만 끈다.
    var hasBorder: Bool = true
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
                    // 큰 글자 설정에서 폭이 모자라면 알약 안에서 두 줄로 꺾여
                    // 캡슐이 찌부러진다. 모양을 지키고 대신 조금 줄인다 -
                    // 말줄임만 두면 긴 문구가 뜻을 잃는다(QA 2026-09-19).
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, CGFloat(JanjanSpacing.m))
            .padding(.vertical, CGFloat(JanjanSpacing.s))
            .background(Capsule(style: .continuous).fill(Color.surface))
            .overlay(
                Capsule(style: .continuous)
                    // hairline 은 흰 카드 위에서 1.25:1 이라 사실상 안 보였다.
                    // 테두리를 붙인 수정(2026-09-19)이 값을 잘못 잡아 증상이
                    // 그대로였다(QA 2026-09-21).
                    .strokeBorder(Color.outline, lineWidth: hasBorder ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 셋(또는 둘) 중 하나를 고르는 답 한 줄. 지나간 시간대에 답할 때 쓴다.
///
/// 두 가지를 고쳤다(QA 2026-09-19).
///
/// · **답이 늘 한 줄에 들어간다.** 알약이 글자 폭만큼만 넓어지면
///   "기억나지 않아요" 가 폭을 넘겨 셋째 답이 아래로 떨어졌다. 주어진 폭을
///   똑같이 나눠 갖게 하고, 글자는 칸 안에서 두 줄로 접히거나 조금 줄어든다 -
///   기분 색 일곱 알약과 같은 약이다.
///
/// · **흰 알약을 쓰지 않는다.** 이 줄은 흰 카드 위에 놓이는데 WhitePillButton
///   도 같은 surface 라 버튼이 배경에 묻혀 글자만 떠 보였다. 한 겹 어두운
///   면(surface2)에 테두리를 둘러, 누를 수 있는 것임이 보이게 한다.
struct AnswerPillRow: View {

    struct Answer: Identifiable {
        /// 한 줄 안에서 같은 문구가 두 번 나오지 않으므로 문구가 곧 식별자다.
        var id: String { title }
        let title: String
        let action: () -> Void

        init(_ title: String, action: @escaping () -> Void) {
            self.title = title
            self.action = action
        }
    }

    let answers: [Answer]

    var body: some View {
        HStack(spacing: CGFloat(JanjanSpacing.xs)) {
            ForEach(answers) { answer in
                Button(action: answer.action) {
                    Text(answer.title)
                        .janjanBody(13, weight: .medium)
                        .multilineTextAlignment(.center)
                        // 두 줄까지 접히고, 그래도 넘치면 조금 줄어든다.
                        // 큰 글자 설정에서도 한 줄을 지키는 마지막 보루다.
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, CGFloat(JanjanSpacing.xs))
                        .padding(.vertical, CGFloat(JanjanSpacing.xs))
                        // maxHeight 를 열어 두면 HStack 이 가장 높은 칸의 높이를
                        // 셋 모두에게 제안한다 - 한 칸만 두 줄이어도 높이가 맞는다.
                        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
                        .background(Capsule(style: .continuous).fill(Color.janjan(.surface2)))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.janjan(.line2), lineWidth: 1)
                        )
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
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
                        // 글자 크게(AX)에서 "미정으로 되돌리기" 가 두 줄로
                        // 꺾여 캡슐 위아래로 삐져나갔다(QA 2026-09-21).
                        // 흰 알약 버튼이 이미 쓰는 처방이다.
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, CGFloat(JanjanSpacing.m))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
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
        Text(Janjan.medicalDisclaimer(JanjanLanguage.current))
            .janjanBody(12)
            .foregroundStyle(Color.muted)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 흰 카드 안에 들어가는 한 줄 입력칸.
///
/// 예전에는 테두리도 바탕도 없이 라벨과 여백으로만 나눴다 — 화면에 선을
/// 늘리지 않으려는 뜻이었는데, 흰 카드 위의 맨 글자는 **입력칸으로 보이지
/// 않았다.** "뭐가 버튼인지 어디가 입력이 되는지도 모르겠고"(사용자,
/// TestFlight 17). 그래서 연회색 바탕을 깐다 — 선을 긋지 않으면서도
/// 누를 자리가 어디까지인지 눈에 보인다. 용량 변경 시트가 이미 같은
/// 모양을 쓰고 있었으니, 앱 안에서 입력칸은 이제 하나로 보인다.
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
                .padding(.horizontal, CGFloat(JanjanSpacing.s))
                // 한 줄 입력칸도 누르는 자리는 44pt 를 지킨다.
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.row), style: .continuous)
                        .fill(Color.janjan(.surface2))
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 키보드를 내리는 한 줄.
///
/// `FocusState` 로 하려면 입력칸을 가진 화면마다 상태를 만들고 칸마다 이어
/// 줘야 하는데, 입력칸이 `JanjanField` 안에 들어 있어서 화면 쪽에서는 잡을
/// 수가 없다. 첫 응답자에게 바로 말하면 어느 칸이 열려 있든 같은 한 줄로 닫힌다.
enum JanjanKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

/// 입력칸이 있는 화면에 붙이는 키보드 손잡이.
///
/// 키보드 위에 "완료" 를 놓고, 스크롤로도 내려갈 수 있게 한다. 예전에는
/// 진료 기록 화면에 둘 다 없어서 한 번 입력하고 나면 키보드가 화면을 덮은
/// 채 저장 버튼까지 가릴 수 없었다(사용자, TestFlight 17).
///
/// **화면마다 한 번만** 붙인다 - 칸마다 붙이면 같은 막대가 여러 개 쌓인다.
struct KeyboardDoneBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(t("완료", "Done")) { JanjanKeyboard.dismiss() }
                        .janjanBody(16, weight: .medium)
                        .foregroundStyle(Color.ink)
                }
            }
    }
}

extension View {
    /// 키보드 위 "완료" 와 스크롤로 내리기. 입력칸이 있는 화면에 한 번 붙인다.
    func keyboardDoneBar() -> some View { modifier(KeyboardDoneBar()) }
}

/// 숫자만 적힌 용량 칸 아래에 뜨는 단위 고르개.
///
/// "모든 약 용량 부분에는 단위가 붙어야 돼"(사용자 2026-09-21). 단위를 앱이
/// 대신 지어내면 10정을 10mg 이라고 적는 일이 생기므로 붙여 주지는 않는다 —
/// 대신 한 번 누르면 붙게 해서, 적는 쪽이 수고롭지 않게 한다.
struct StrengthUnitRow: View {

    @Binding var text: String

    /// 정신과 처방에서 실제로 쓰이는 것만. 목록이 길면 고르는 데가 아니라
    /// 읽는 데가 된다.
    private static let units = ["mg", "mcg", "mL"]

    /// 단위를 붙인 표기. `mg` 는 붙여 쓰고 `tabs` 같은 단어형은 띄운다 -
    /// "10tabs" 는 영어로 읽히지 않는다(QA 2026-09-21).
    private func appending(_ unit: String, to text: String) -> String {
        let base = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsSpace = unit.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
            && unit.count > 3
        return needsSpace ? "\(base) \(unit)" : base + unit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
            Text(t("단위까지 적어 주세요. 용량이면 10mg, 개수면 2개처럼요.",
                   "Add the unit too — 10mg for a strength, 2 pills for a count."))
                .janjanBody(12)
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                ForEach(Self.units + [t("정", "tabs"), t("개", "pills")], id: \.self) { unit in
                    // **입력칸과 같은 바탕을 쓰지 않는다.** 둘 다 surface2 였을 때
                    // 방금 바탕을 깔아 구분한 입력칸과 그 아래 알약이 한 덩어리로
                    // 보였다(QA 2026-09-21). 누르는 것은 흰 면에 테두리를 준다.
                    Button {
                        text = appending(unit, to: text)
                    } label: {
                        Text(unit)
                            .janjanBody(14, weight: .medium)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.janjan(.surface))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.outline, lineWidth: 1)
                            )
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(t("단위 \(unit) 붙이기", "Add unit \(unit)")))
                }
            }
        }
    }
}

/// 용량 표기에 단위가 빠졌는지. 빈 칸은 괜찮다 — 용량은 선택이다.
///
/// 소수점·쉼표·가운뎃점·빗금까지는 숫자의 일부로 본다("0.5", "1/2").
///
/// **숫자와 단위가 둘 다 있어야 통과한다.** 예전에는 "숫자만 있는가" 만 물어서
/// `"mg"` 한 마디가 단위 있음으로 통과했고, 목록에 "약 이름 mg" 가 남았다
/// (QA 2026-09-21).
func strengthNeedsUnit(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    let numeric = CharacterSet(charactersIn: "0123456789.,/·- ")
    let hasDigit = trimmed.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
    let hasUnit = trimmed.unicodeScalars.contains { !numeric.contains($0) }
    return !(hasDigit && hasUnit)
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

    /// VoiceOver 가 부를 말. 글자가 "3" 처럼 그 자체로는 뜻이 없을 때 준다 -
    /// 제목은 별도 요소라 버튼과 이어지지 않는다(QA 2026-09-21).
    var accessibilityLabel: String?

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .janjanBody(14, weight: .medium)
                // 알약 안에서 줄바꿈되면 캡슐이 찌부러진다. 모양을 지키고 말줄임한다.
                .lineLimit(1)
                // 말줄임되기 전에 글자를 조금 줄여 본다 - "술 마셨어요" 같은
                // 긴 라벨이 좁은 기기에서 "술 마셨…" 로 깨지지 않게.
                .minimumScaleFactor(0.85)
                .foregroundStyle(Color.janjan(isOn ? .surface : .ink2))
                .frame(minWidth: minWidth)
                .padding(.horizontal, CGFloat(fillsRow ? JanjanSpacing.xs : JanjanSpacing.s))
                .padding(.vertical, CGFloat(JanjanSpacing.xs))
                .frame(maxWidth: fillsRow ? .infinity : nil)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.janjan(isOn ? .ink : .surface2))
                )
                // 캡슐 자체는 34pt 안팎으로 아담하지만, 누르는 자리는 44pt 를
                // 지킨다 - 요일처럼 일곱 개가 붙는 줄에서 오탭을 막는 보이지 않는 여유.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel ?? text))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : [.isButton])
    }
}

/// 숫자를 하나씩 올리고 내리는 줄.
///
/// 시스템 `Stepper` 는 회색 시스템 컨트롤이라 "칩과 버튼은 완전한 알약" 규칙(설계 02절)과
/// 어긋난다. 개수·세기·시간처럼 눈금이 있는 값은 전부 이걸 쓴다.
struct CountStepper: View {

    let text: String
    var decreaseLabelKo: String = t("줄이기", "Decrease")
    var increaseLabelKo: String = t("늘리기", "Increase")
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

/// 가려진 약 이름. Pro 의 "약 이름 가리기"가 켜졌을 때 이름 대신 놓는다.
///
/// 누르면 그 자리에서만 원래 글자가 보이고, 다시 누르면 도로 가려진다. 이 뷰
/// 자신은 화면 전환을 기억하지 않는다 — 시트를 닫거나 다른 화면으로 갔다 오면
/// 뷰가 새로 만들어지며 `isRevealed` 도 처음(false)으로 돌아가, 굳이 다시
/// 가리는 코드 없이도 자연히 다시 가려진다.
///
/// 글자 수 자체가 힌트가 되지 않도록 이름 길이·개수와 무관하게 점 셋로 고정한다
/// (`maskGlyph`). 색만으로 가림·펼침을 말하지 않고 글자(점 또는 이름)로 말한다.
///
/// 폰트·색은 이 뷰가 정하지 않는다 — 두 상태(점 · 이름) 모두 평범한 `Text` 라서
/// 바깥에서 `.janjanBody(...)`, `.foregroundStyle(...)` 를 그대로 얹으면
/// 환경값으로 내려가 그대로 먹는다. 자리마다 글꼴·색이 다른 다섯 화면에서
/// 매번 같은 파라미터를 받게 만드는 대신, 쓰는 자리의 기존 수식어를 그대로
/// 재사용할 수 있게 한 것 - 사용처마다 새 스타일 인자를 늘리지 않는다.
///
/// 이미 다른 손짓(행 전체 내비게이션 등)이 같은 자리를 차지한 곳에는 이 뷰를
/// 그대로 쓰지 않는다 — 각 화면의 판단은 그 화면의 편집 기록에 남겨 둔다.
struct MaskedNameText: View {

    let name: String
    var isMasked: Bool

    /// 가렸을 때 VoiceOver 가 이 약을 부르는 말(대개 용도 한 줄).
    ///
    /// 없으면 전부 "가려진 약 이름" 으로만 읽혀, 비상약 목록이나 시간대
    /// 시트를 넘길 때 어느 줄인지 구별되지 않는다(QA 2026-09-21).
    /// 진료 기록 폼과 워치 스냅샷은 이미 용도로 부르는 규칙을 쓰고 있다.
    var spokenWhenMasked: String?

    @State private var isRevealed = false

    /// 가려졌을 때 보이는 점 표기. `TogglePill` 처럼 블러를 못 쓰는 자리
    /// (누르면 다른 동작이 일어나는 캡슐 안)에서 쓰려고 남겨 둔다.
    static let maskGlyph = "● ● ●"

    /// 뿌옇게 가리는 세기. 15pt 안팎의 글자가 형체만 남고 읽히지 않는 값.
    /// 점 표기 대신 블러를 쓰는 것은 사용자 결정(2026-09-16) - 모자이크처럼
    /// 보이게 하고, 누르면 글자로 보인다.
    static let blurRadius: CGFloat = 6

    var body: some View {
        if !isMasked {
            Text(name)
        } else if isRevealed {
            Text(name)
                .contentShape(Rectangle())
                .onTapGesture { isRevealed = false }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text(t("누르면 가려요", "Tap to hide")))
        } else {
            Text(name)
                // 블러는 글자 상자 밖으로 번진다. 예전에는 상자 경계에서
                // 잘라 냈는데(.clipped), 그러면 뿌연 글자의 가장자리가 칼로
                // 자른 듯 끊겼다 - 24pt 여러 줄 이름에서는 모자이크가 아니라
                // 깨진 그림처럼 보였다(QA 2026-09-21). 번질 자리를 먼저
                // 확보하고 다시 제자리 크기로 돌린다.
                .padding(-Self.blurRadius)
                .blur(radius: Self.blurRadius)
                .padding(Self.blurRadius)
                .contentShape(Rectangle())
                .onTapGesture { isRevealed = true }
                // VoiceOver 가 진짜 이름을 읽으면 가림이 뚫린다 - 라벨을 통째로 바꾼다.
                .accessibilityLabel(Text(spokenWhenMasked ?? t("가려진 약 이름", "Hidden medication name")))
                .accessibilityHint(Text(t("누르면 보여요", "Tap to show")))
                .accessibilityAddTraits(.isButton)
        }
    }
}
