import SwiftUI
import WatchKit
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

    /// 좌우 여백. 시스템 여백에 맡기면 왼쪽 4에 오른쪽 58 로 치우쳤다
    /// (런 40 사용자 발견) - 기분 화면처럼 화면 폭에서 직접 계산한다.
    private let sideMargin: CGFloat = 12

    private var contentWidth: CGFloat {
        WKInterfaceDevice.current().screenBounds.width - sideMargin * 2
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // 이름을 한 줄로 묶는다 - 세로 나열이면 41mm 에서 건너뜀이
                    // 화면 밖으로 밀려 굴려야 눌렸다(사용자 발견 2026-09-18).
                    Text(slot.medicationNames.joined(separator: "\u{00A0}· "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(3)

                    // 두 버튼은 같은 스타일 - 다른 스타일(채움/테두리)을 섞으면
                    // 안쪽 여백이 달라 폭이 어긋나 보인다. 위계는 색으로만 가른다.
                    Button {
                        record(.taken)
                    } label: {
                        Text(takenTitle)
                            // "전부 먹었어요" 는 "전부 건너뜀" 보다 길다. 한쪽만
                            // 두 줄로 꺾이면 두 버튼의 높이가 어긋난다(QA 2026-09-19).
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green.opacity(0.7))
                    .padding(.top, 2)

                    Button {
                        record(.skipped)
                    } label: {
                        Text(skippedTitle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray.opacity(0.35))

                    Text(t(
                        "하나만 따로 기록하는 건 아이폰에서 할 수 있어요.",
                        "You can log a single med on your iPhone."
                    ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                // 모든 줄을 같은 폭으로 묶어 화면 한가운데 놓는다 - 버튼과
                // 안내문이 같은 왼끝·오른끝을 갖는다.
                .frame(width: contentWidth)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(titleText)
        }
    }

    /// 한 번 눌러 그 시간대의 약 전부를 기록한다. 약이 둘 이상이면 버튼이
    /// 그렇게 말한다 - 잠금화면 알림의 "전부 복용함" 과 같은 규칙이다.
    private var coversManyMedications: Bool { slot.medicationIDs.count > 1 }

    private var takenTitle: String {
        coversManyMedications ? t("전부 먹었어요", "All taken") : t("먹었어요", "Took it")
    }

    private var skippedTitle: String {
        coversManyMedications ? t("전부 건너뜀", "Skip all") : t("건너뜀", "Skipped")
    }

    private var titleText: String {
        // 직접 넣은 시간대는 이름이 곧 시각이라 두 번 말하지 않는다.
        slot.timeText.isEmpty ? slot.labelKo : "\(slot.labelKo) \(slot.timeText)"
    }

    private func record(_ action: WatchMessage.DoseAction) {
        // 손목 진동으로 눌렸음을 알린다 - 화면을 보지 않고 누르는 경우가 많다.
        WKInterfaceDevice.current().play(action == .taken ? .success : .click)
        session.send(.doseAction(
            medicationIDs: slot.medicationIDs,
            slotKey: slot.slotKey,
            action: action,
            at: Date()
        ))
        // 폰의 새 스냅샷을 기다리지 않고 화면부터 완료로 바꾼다 - 안 그러면
        // 같은 줄이 미완료로 남아 두 번 누르게 된다. 진짜 스냅샷이 오면 덮인다.
        session.markSlotCompleted(slot.slotKey)
        dismiss()
    }
}

#Preview {
    DoseQuickView(slot: WatchSnapshot.SlotLine(
        slotKey: "bedtime",
        labelKo: "자기전",
        timeText: "22:30",
        medicationNames: ["라모트리진", "쿠에티아핀"],
        medicationIDs: [],
        isCompleted: false
    ))
    .environmentObject(WatchSessionManager.shared)
}
