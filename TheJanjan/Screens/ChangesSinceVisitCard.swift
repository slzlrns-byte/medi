import SwiftUI
import SwiftData
import JanjanCore

/// "지난 진료 이후 약 변경" — 약마다 바뀌었는지 그대로인지.
///
/// 진료실에서 가장 자주 나오는 물음이 "그때 뭐 바꾸셨죠?" 인데, 그걸 보려면
/// 약을 하나씩 열어 봐야 했다(사용자 요청 2026-09-21).
///
/// **새 데이터를 만들지 않는다.** 이미 쌓여 있는 것 둘로 뽑는다 -
/// 마지막 진료일(`Prescription.visitDate`)과 그 뒤의 용량 변경(`DoseChange`).
/// 변경이 있으면 "변경", 없으면 "유지" 다. 사용자가 따로 표시할 것이 없다.
///
/// 접어 두는 이유: 대개는 "다 그대로" 이고, 그 줄이 화면을 차지할 이유가 없다.
/// 바뀐 것이 있으면 머리글이 몇 개인지 먼저 말해 준다.
struct ChangesSinceVisitCard: View {

    @Query(sort: \MedicationRecord.createdAt) private var medicationRecords: [MedicationRecord]
    @Query private var doseChangeRecords: [DoseChangeRecord]
    @Query(sort: \PrescriptionRecord.visitDate, order: .reverse)
    private var prescriptionRecords: [PrescriptionRecord]

    @State private var isExpanded = false

    private var lang: JanjanLanguage { .current }
    private var masksNames: Bool { JanjanPrivacy.hidesNames }

    /// 마지막 진료일. 없으면 이 카드 자체를 그리지 않는다 -
    /// 기준이 없으면 "그 이후" 가 성립하지 않는다.
    private var lastVisit: Date? {
        prescriptionRecords.first?.core.visitDate
    }

    private struct Row: Identifiable {
        let id: UUID
        let name: String
        /// 바뀐 내용. nil 이면 그대로다.
        let change: DoseChange?
        /// 지금 적혀 있는 용량. 변경이 없을 때 이것을 보여 준다.
        let strength: String
    }

    private var rows: [Row] {
        guard let lastVisit else { return [] }
        let since = Calendar.current.startOfDay(for: lastVisit)
        let changes = doseChangeRecords.map(\.core).filter { $0.changedAt >= since }

        return medicationRecords
            .map(\.core)
            .filter { $0.status == .active }
            .map { medication in
                Row(
                    id: medication.id,
                    name: medication.name,
                    change: changes
                        .filter { $0.medicationID == medication.id }
                        .max(by: { $0.changedAt < $1.changedAt }),
                    strength: medication.strengthText
                )
            }
    }

    private var changedCount: Int {
        rows.filter { $0.change != nil }.count
    }

    var body: some View {
        if lastVisit != nil, !rows.isEmpty {
            JanjanCard {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                    header
                    if isExpanded {
                        VStack(spacing: CGFloat(JanjanSpacing.xs)) {
                            ForEach(rows) { row in
                                rowView(row)
                            }
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: CGFloat(JanjanSpacing.xs)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("지난 진료 이후 약 변경", "Medication changes since your visit"))
                        .janjanDisplay(18)
                        .foregroundStyle(Color.ink)
                    Text(summary)
                        .janjanBody(12)
                        .foregroundStyle(Color.muted)
                }
                Spacer(minLength: CGFloat(JanjanSpacing.xs))
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.janjan(.line2))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // SwiftUI 에는 accessibilityExpanded 가 없다(UIKit 쪽 API 다).
        // 상태는 값으로, 다음에 일어날 일은 힌트로 나눠 말한다 - 힌트만
        // 있으면 지금 펼쳐져 있는지를 끝까지 들어야 알 수 있다.
        .accessibilityValue(Text(isExpanded ? t("펼쳐짐", "Expanded") : t("접힘", "Collapsed")))
        .accessibilityHint(Text(isExpanded ? t("눌러서 접습니다", "Tap to collapse")
                                           : t("눌러서 펼칩니다", "Tap to expand")))
    }

    private var summary: String {
        guard let lastVisit else { return "" }
        let day = ReportComposer.monthDayText(lastVisit, language: lang)
        if changedCount == 0 {
            return t("\(day) 이후 \(rows.count)개 모두 그대로예요.",
                     "All \(rows.count) unchanged since \(day).")
        }
        return t("\(day) 이후 \(changedCount)개가 바뀌었어요.",
                 "\(changedCount) changed since \(day).")
    }

    private func rowView(_ row: Row) -> some View {
        HStack(alignment: .top, spacing: CGFloat(JanjanSpacing.s)) {
            VStack(alignment: .leading, spacing: 2) {
                MaskedNameText(name: row.name, isMasked: masksNames)
                    .janjanBody(15, weight: .medium)
                    .foregroundStyle(Color.ink)
                if let change = row.change {
                    Text(change.arrowTextKo)
                        .janjanBody(13)
                        .foregroundStyle(Color.ink2)
                    if let note = change.note?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !note.isEmpty {
                        Text(note)
                            .janjanBody(12)
                            .foregroundStyle(Color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if !row.strength.isEmpty {
                    Text(row.strength)
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)
                }
            }

            Spacer(minLength: CGFloat(JanjanSpacing.xs))

            // 알약을 씌우니 눌리는 것처럼 보였다(사용자, 2026-09-21). 이건
            // 손잡이가 아니라 상태라서, 바탕을 걷고 글자만 남긴다 - 이 화면에서
            // 캡슐은 누르는 것들이 쓰고 있다. 색만으로 말하지 않는 규칙은
            // 그대로다: 글자가 늘 함께 온다.
            Text(row.change != nil ? t("변경됨", "Changed") : t("유지됨", "Unchanged"))
                .janjanBody(13, weight: row.change != nil ? .medium : .regular)
                .foregroundStyle(Color.janjan(row.change != nil ? .peachInk : .muted))
                .fixedSize()
        }
        .padding(.vertical, CGFloat(JanjanSpacing.xxs))
    }
}
