import SwiftUI
import SwiftData
import JanjanCore

/// 지난 진료 기록 (Pro 경계 2026-09-19 결정).
///
/// 이번(가장 최근) 진료와 바로 이전 회차까지는 무료다 — "지난번에 뭘 받았더라"
/// 는 이 앱의 기본 예의라서. 그보다 오래된 이력이 Pro 다. 쌓인 기록이 계속 쓸
/// 이유가 되게 하되, 무료였던 것을 나중에 잠그거나 개수를 제한하는 방식은
/// 쓰지 않는다 — 이 화면 자체가 새 기능이고, 경계는 처음부터 이렇다.
struct VisitHistoryView: View {

    @EnvironmentObject private var pro: ProStore
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PrescriptionRecord.visitDate, order: .reverse)
    private var prescriptionRecords: [PrescriptionRecord]
    @Query private var medicationRecords: [MedicationRecord]

    /// 무료로 선명하게 보이는 최근 회차 수: 이번 진료 + 바로 이전 회차.
    static let freeClearVisits = 2

    private var today: Date { Date() }
    private var lang: JanjanLanguage { .current }

    /// 약 이름 가리기가 실제로 적용되는지. Pro 가 아니면 켜져 있어도 아무 일도 하지 않는다.
    private var masksNames: Bool { pro.isPro && JanjanPrivacy.hidesNames }

    /// 실제로 다녀온 진료만. 오늘 탭에서 일정만 잡아 둔 기록(약·일수·메모 없음)은
    /// 진료가 아니라 세지 않는다 — ReportView 의 lastVisit 과 같은 규칙.
    private var visits: [PrescriptionRecord] {
        prescriptionRecords
            .filter { !($0.medicationIDValues.isEmpty && $0.daysSupplied == 0 && $0.clinicNote.isEmpty) }
            .filter { $0.visitDate <= today }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CGFloat(JanjanSpacing.s)) {
                    if visits.isEmpty {
                        emptyCard
                    } else {
                        ForEach(Array(visits.prefix(Self.freeClearVisits))) { record in
                            visitCard(record, isBlurred: false)
                        }
                        if visits.count > Self.freeClearVisits {
                            olderSection
                        }
                    }
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.top, CGFloat(JanjanSpacing.s))
                .padding(.bottom, CGFloat(JanjanSpacing.xxl))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle(t("지난 진료 기록", "Visit history"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(t("닫기", "Close")) { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
        }
    }

    /// 세 회차째부터. 무료에게는 날짜만 남기고 내용이 흐려지며, 누르면 페이월이 열린다.
    /// 배지가 카드마다 붙지 않게 묶음 전체에 문 하나만 단다.
    @ViewBuilder
    private var olderSection: some View {
        let older = Array(visits.dropFirst(Self.freeClearVisits))
        if pro.isPro {
            ForEach(older) { record in
                visitCard(record, isBlurred: false)
            }
        } else {
            VStack(spacing: CGFloat(JanjanSpacing.s)) {
                ForEach(older) { record in
                    visitCard(record, isBlurred: true)
                }
            }
            .proGated(.visitHistory)
        }
    }

    // MARK: - 카드

    private var emptyCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                Text(t("아직 진료 기록이 없어요", "No visit records yet"))
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)
                Text(t(
                    "약 탭의 \"처방 기록하기\" 로 남긴 진료가 여기 회차별로 쌓여요.",
                    "Visits you log with \"Log a prescription\" on the Meds tab stack up here."
                ))
                    .janjanBody(13)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func visitCard(_ record: PrescriptionRecord, isBlurred: Bool) -> some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                // 날짜는 흐려도 남는다 - 어느 진료가 잠겨 있는지는 보여야
                // 무엇을 여는지 알고 결정할 수 있다.
                HStack(alignment: .firstTextBaseline, spacing: CGFloat(JanjanSpacing.xs)) {
                    Text(visitDateText(record.visitDate))
                        .janjanBody(15, weight: .semibold)
                        .foregroundStyle(Color.ink)
                    Spacer(minLength: 0)
                    if record.daysSupplied > 0 {
                        PillChip(text: t("\(record.daysSupplied)일치", "\(record.daysSupplied) days"))
                    }
                }

                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                    medicationLine(record)

                    if !record.clinicNote.isEmpty {
                        Text(record.clinicNote)
                            .janjanBody(13)
                            .foregroundStyle(Color.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .blur(radius: isBlurred ? 5 : 0)
            }
        }
    }

    @ViewBuilder
    private func medicationLine(_ record: PrescriptionRecord) -> some View {
        let names = medicationNames(record)
        if masksNames || names.isEmpty {
            // 이름을 가리는 중이거나(가린 이름이 여기서 새면 안 된다),
            // 그 약이 이미 지워져 이름을 되찾을 수 없을 때는 개수로만 말한다.
            if !record.medicationIDValues.isEmpty {
                Text(t("약 \(record.medicationIDValues.count)개", "\(record.medicationIDValues.count) medications"))
                    .janjanBody(13)
                    .foregroundStyle(Color.muted)
            }
        } else {
            FlowRow(spacing: CGFloat(JanjanSpacing.xs)) {
                ForEach(names, id: \.self) { name in
                    PillChip(text: name)
                }
            }
        }
    }

    private func medicationNames(_ record: PrescriptionRecord) -> [String] {
        record.medicationIDValues.compactMap { value in
            medicationRecords.first { $0.id.uuidString == value }?.core.displayReady.name
        }
    }

    private func visitDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: lang.localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: date)
    }
}

#Preview {
    VisitHistoryView()
        .modelContainer(for: JanjanSchema.allModels, inMemory: true)
        .environmentObject(ProStore())
}
