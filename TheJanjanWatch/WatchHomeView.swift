import SwiftUI
import JanjanCore

/// 워치 홈 — 스크롤 없이 한 화면 (설계 10절).
/// 오늘의 시간대 목록 + 증상 기록 / 기분 두 버튼. 나머지는 아이폰으로.
struct WatchHomeView: View {

    @EnvironmentObject private var session: WatchSessionManager

    @State private var isShowingSymptom = false
    @State private var isShowingMood = false

    var body: some View {
        NavigationStack {
            List {
                if session.snapshot.slots.isEmpty {
                    Text("아이폰에서 약을 등록하면 여기 나옵니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.snapshot.slots) { slot in
                        slotRow(slot)
                    }
                }

                Button("증상 기록") { isShowingSymptom = true }
                Button("기분") { isShowingMood = true }

                Text("자세한 건 iPhone에서")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            .navigationTitle(navigationTitleText)
            .sheet(isPresented: $isShowingSymptom) {
                SymptomQuickEntryView()
                    .environmentObject(session)
            }
            .sheet(isPresented: $isShowingMood) {
                MoodQuickView()
                    .environmentObject(session)
            }
        }
    }

    private var navigationTitleText: String {
        let text = session.snapshot.dateText
        return text == "—" ? "오늘" : "오늘 \(text)"
    }

    private func slotRow(_ slot: WatchSnapshot.SlotLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(slot.labelKo)
                    .font(.headline)
                Spacer()
                Text(slot.isCompleted ? "완료" : slot.timeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(slot.medicationNames.isEmpty ? slot.summaryKo : slot.medicationNames.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    WatchHomeView()
        .environmentObject(WatchSessionManager.shared)
}
