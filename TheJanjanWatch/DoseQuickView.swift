import SwiftUI
import JanjanCore

/// 복약 원탭 — 한 시간대를 통째로 기록한다 (설계 10절).
///
/// 워치는 약마다 따로 답하지 않는다. 작은 화면에서 세 번 누르게 하느니
/// 한 번에 끝내고, 하나만 건너뛰는 드문 경우는 아이폰이 맡는다.
/// 저장은 폰이 한다 — 여기서는 사건만 던지고 닫는다.
struct DoseQuickView: View {

    let slot: WatchSnapshot.SlotLine

    @EnvironmentObject private var session: WatchSessionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(slot.medicationNames, id: \.self) { name in
                        Text(name)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        record(.taken)
                    } label: {
                        Text("먹었어요")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green.opacity(0.7))
                    .padding(.top, 6)

                    Button {
                        record(.skipped)
                    } label: {
                        Text("건너뜀")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Text("하나만 따로 기록하는 건 아이폰에서 할 수 있어요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle(titleText)
        }
    }

    private var titleText: String {
        // 직접 넣은 시간대는 이름이 곧 시각이라 두 번 말하지 않는다.
        slot.timeText.isEmpty ? slot.labelKo : "\(slot.labelKo) \(slot.timeText)"
    }

    private func record(_ action: WatchMessage.DoseAction) {
        session.send(.doseAction(
            medicationIDs: slot.medicationIDs,
            slotKey: slot.slotKey,
            action: action
        ))
        dismiss()
    }
}

#Preview {
    DoseQuickView(slot: WatchSnapshot.SlotLine(
        slotKey: "bedtime",
        labelKo: "취침",
        timeText: "22:30",
        medicationNames: ["라모트리진", "쿠에티아핀"],
        medicationIDs: [],
        isCompleted: false
    ))
    .environmentObject(WatchSessionManager.shared)
}
