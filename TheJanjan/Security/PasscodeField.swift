import SwiftUI
import JanjanCore

/// 네 자리를 받는 화면 조각. 잠금 화면과 번호 정하기가 같은 것을 쓴다.
///
/// 시스템 키보드를 쓰지 않고 숫자판을 직접 그린다. 숫자만 받는 화면에 글자 키보드가
/// 올라왔다 내려갔다 하는 것이 이 앱의 결이 아니고, 잠금 화면에서는 키보드가
/// 화면을 반쯤 가리기 때문이다.
struct PasscodeField: View {

    /// 지금까지 눌린 숫자.
    @Binding var digits: String
    /// 네 자리가 다 차면 부른다. 사용자가 "확인" 을 한 번 더 누르지 않아도 되게.
    let onComplete: (String) -> Void

    /// 눌러도 아무 일이 없어야 하는 동안(기다리는 중).
    var isDisabled = false

    private let keys: [[Key]] = [
        [.digit("1"), .digit("2"), .digit("3")],
        [.digit("4"), .digit("5"), .digit("6")],
        [.digit("7"), .digit("8"), .digit("9")],
        [.blank, .digit("0"), .backspace]
    ]

    private enum Key: Hashable {
        case digit(String)
        case backspace
        case blank
    }

    var body: some View {
        VStack(spacing: CGFloat(JanjanSpacing.xl)) {
            dots
            pad
        }
    }

    // MARK: - 점 네 개

    private var dots: some View {
        HStack(spacing: CGFloat(JanjanSpacing.m)) {
            ForEach(0..<Passcode.length, id: \.self) { index in
                Circle()
                    .fill(index < digits.count ? Color.ink : Color.janjan(.surface2))
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle().strokeBorder(Color.hairline, lineWidth: index < digits.count ? 0 : 1)
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("네 자리 중 \(digits.count)자리 입력됨"))
    }

    // MARK: - 숫자판

    private var pad: some View {
        VStack(spacing: CGFloat(JanjanSpacing.m)) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, row in
                HStack(spacing: CGFloat(JanjanSpacing.xl)) {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
        }
        .opacity(isDisabled ? 0.4 : 1)
        .disabled(isDisabled)
    }

    @ViewBuilder
    private func keyButton(_ key: Key) -> some View {
        switch key {
        case .blank:
            // 자리를 지켜 0 이 가운데 오게 한다.
            Color.clear.frame(width: 72, height: 72)

        case .digit(let value):
            Button {
                append(value)
            } label: {
                Text(value)
                    .font(JanjanFont.display(30))
                    .foregroundStyle(Color.ink)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color.surface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(value))

        case .backspace:
            Button {
                removeLast()
            } label: {
                Image(systemName: "delete.left")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.ink2)
                    .frame(width: 72, height: 72)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("지우기"))
            .opacity(digits.isEmpty ? 0.3 : 1)
            .disabled(digits.isEmpty)
        }
    }

    // MARK: - 입력

    private func append(_ value: String) {
        guard digits.count < Passcode.length else { return }
        digits += value

        if digits.count == Passcode.length {
            let entered = digits
            // 네 번째 점이 채워지는 것을 눈으로 본 뒤에 넘어가게 한 박자 둔다.
            // 곧바로 넘기면 마지막 숫자가 들어갔는지 알 수 없다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                onComplete(entered)
            }
        }
    }

    private func removeLast() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
    }
}
