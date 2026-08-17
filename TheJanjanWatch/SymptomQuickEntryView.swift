import SwiftUI
import JanjanCore

/// 증상 빠른기록 — 세 화면, 10초 (설계 10절).
/// 자주 쓰는 증상 6개 → 크라운으로 세기 → 저장.
struct SymptomQuickEntryView: View {

    @EnvironmentObject private var session: WatchSessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var selected: SymptomItem?

    private let items = Catalogs.watchQuickSymptoms

    var body: some View {
        NavigationStack {
            if let item = selected {
                SeverityPicker(item: item) { severity in
                    session.send(.symptom(symptomID: item.id, severity: severity, at: Date()))
                    dismiss()
                }
            } else {
                List {
                    ForEach(items) { item in
                        Button(item.nameKo) { selected = item }
                    }
                }
                .navigationTitle("증상")
            }
        }
    }
}

/// 0–10 세기를 디지털 크라운으로 고른다.
private struct SeverityPicker: View {

    let item: SymptomItem
    let onSave: (Int) -> Void

    @State private var value: Double = 5
    @FocusState private var isCrownFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(item.nameKo)
                .font(.headline)
                .lineLimit(2)

            Text("\(Int(value.rounded()))")
                .font(.system(size: 44, weight: .light))
                .monospacedDigit()
                .focusable()
                .focused($isCrownFocused)
                .digitalCrownRotation(
                    $value,
                    from: 0,
                    through: 10,
                    by: 1,
                    sensitivity: .low,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )

            Text("세기 · 크라운으로 조절")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("저장") {
                onSave(Int(value.rounded()))
            }
        }
        .padding(.horizontal, 4)
        .onAppear { isCrownFocused = true }
    }
}

#Preview {
    SymptomQuickEntryView()
        .environmentObject(WatchSessionManager.shared)
}
