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
                if !session.snapshot.isPro {
                    // 워치 앱 전체가 Pro 다. 반쯤 동작하게 두지 않고 여기서 멈춘다.
                    // 결제는 워치에서 받지 않는다 — 작은 화면에서 되돌릴 수 없는
                    // 결정을 받지 않기 위해서다.
                    Text("워치 앱은 Pro 기능이에요.")
                        .font(.footnote)
                    Text("아이폰의 설정에서 Pro 를 켜면 여기에 오늘 일정이 나와요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if session.snapshot.slots.isEmpty {
                    Text("아이폰에서 약을 등록하면 여기 나옵니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.snapshot.slots) { slot in
                        slotRow(slot)
                    }
                }

                if session.snapshot.isPro {
                    Button("증상 기록") { isShowingSymptom = true }
                    Button("기분") { isShowingMood = true }
                }

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
