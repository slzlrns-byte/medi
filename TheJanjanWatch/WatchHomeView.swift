import SwiftUI
import JanjanCore

/// 워치 홈 — 스크롤 없이 한 화면 (설계 10절).
/// 오늘의 시간대 목록 + 증상 기록 / 기분 두 버튼. 나머지는 아이폰으로.
struct WatchHomeView: View {

    @EnvironmentObject private var session: WatchSessionManager

    @State private var isShowingSymptom = false
    @State private var isShowingMood = false
    /// 눌러서 기록할 시간대. nil 이면 시트가 닫혀 있다.
    @State private var openSlot: WatchSnapshot.SlotLine?

    #if DEBUG
    /// 화면 찍기용 시트를 두 번 열지 않기 위한 표시.
    @State private var hasOpenedRequestedScreen = false
    #endif

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

                if session.lastSendWasQueued {
                    // 전송이 큐에 쌓였다는 사실을 숨기지 않는다 - 시트가 닫혔다고
                    // 폰에 이미 적혔다고 믿게 두면 안 된다.
                    Text("아이폰과 만나면 방금 기록이 전달돼요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                Text("자세한 건 iPhone에서")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            .navigationTitle(navigationTitleText)
            // 구독이 끝난 스냅샷이 오면 열려 있던 시트도 닫는다 - 잠긴 기능이
            // 시트 안에서 반쯤 살아 있으면, 거기서 보낸 기록을 폰이 버린다.
            .onChange(of: session.snapshot.isPro) { _, isPro in
                if !isPro {
                    isShowingMood = false
                    isShowingSymptom = false
                    openSlot = nil
                }
            }
            .onAppear {
                // 화면에 돌아올 때마다 최신 그림을 청한다. 폰의 push 가 유실됐어도
                // 여기서 따라잡는다 - 워치에는 당겨서 새로고침이 없다.
                session.requestSnapshot()
                // watchOS 는 XCUITest 가 없어 눌러서 열 수 없다. 화면을 찍을 때만
                // 실행 인자로 어느 시트를 열지 고른다.
                //
                // onAppear 안에서 곧바로 시트를 켜면 계층이 자리를 잡기 전이라
                // SwiftUI 가 그 표시를 흘려보낸다. 한 박자 뒤로 미룬다.
                // onAppear 는 시트를 닫고 돌아올 때도 다시 불리므로 한 번만 연다.
                #if DEBUG
                guard !hasOpenedRequestedScreen else { return }
                hasOpenedRequestedScreen = true
                let screen = WatchDemoSeed.requestedScreen
                guard screen != .home else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    switch screen {
                    case .home: break
                    case .mood: isShowingMood = true
                    case .symptom: isShowingSymptom = true
                    case .dose: openSlot = session.snapshot.slots.first { !$0.isCompleted }
                    }
                }
                #endif
            }
            .sheet(isPresented: $isShowingSymptom) {
                SymptomQuickEntryView()
                    .environmentObject(session)
            }
            .sheet(isPresented: $isShowingMood) {
                MoodQuickView()
                    .environmentObject(session)
            }
            .sheet(item: $openSlot) { slot in
                DoseQuickView(slot: slot)
                    .environmentObject(session)
            }
        }
    }

    private var navigationTitleText: String {
        let text = session.snapshot.dateText
        return text == "—" ? "오늘" : "오늘 \(text)"
    }

    /// 아직 답하지 않은 시간대는 눌러서 바로 기록한다. 끝난 줄은 그냥 정보다 —
    /// 되돌리기는 실수하기 쉬운 작은 화면 대신 아이폰이 맡는다.
    ///
    /// **약 ID 가 없는 줄도 눌리지 않는다.** ID 키가 없던 옛 스냅샷인데, ID 없이
    /// 보내면 폰이 무엇을 기록할지 몰라 조용히 버린다(QA 2026-09-10).
    /// 다음 스냅샷이 오면 ID 가 채워져 저절로 눌리게 된다.
    @ViewBuilder
    private func slotRow(_ slot: WatchSnapshot.SlotLine) -> some View {
        if slot.isCompleted || slot.medicationIDs.isEmpty {
            slotRowBody(slot)
        } else {
            Button {
                openSlot = slot
            } label: {
                slotRowBody(slot)
            }
        }
    }

    private func slotRowBody(_ slot: WatchSnapshot.SlotLine) -> some View {
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
