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

    /// 가장 최근 진료 말고 나머지도 펴 둘지(사용자 요청 2026-09-21).
    @State private var isShowingOlder = false

    /// 자정을 넘기면 값이 바뀌어 화면이 다시 그려진다(JanjanClock).
    @ObservedObject private var clock = JanjanClock.shared
    private var today: Date { clock.today }
    private var endOfToday: Date { clock.endOfToday }
    private var lang: JanjanLanguage { .current }

    /// 약 이름 가리기가 실제로 적용되는지. Pro 가 아니면 켜져 있어도 아무 일도 하지 않는다.
    private var masksNames: Bool { JanjanPrivacy.hidesNames }

    /// 실제로 다녀온 진료만. 오늘 탭에서 일정만 잡아 둔 기록(약·일수·메모 없음)은
    /// 진료가 아니라 세지 않는다 — ReportView 의 lastVisit 과 같은 규칙.
    private var visits: [PrescriptionRecord] {
        prescriptionRecords
            .filter { !($0.medicationIDValues.isEmpty && $0.daysSupplied == 0 && $0.clinicNote.isEmpty) }
            // 오늘 낮에 적은 진료가 빠지지 않게 하루의 끝과 견준다.
            .filter { $0.visitDate < endOfToday }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CGFloat(JanjanSpacing.s)) {
                    if visits.isEmpty {
                        emptyCard
                    } else {
                        // 가장 최근 진료만 펴 두고 나머지는 접는다. 진료를
                        // 오래 다닐수록 이 목록이 길어지는데, 대개 보러 오는
                        // 것은 "지난번에 뭐 받았더라" 하나다(사용자 2026-09-21).
                        if let latest = visits.first {
                            visitCard(latest, isBlurred: false)
                        }
                        if visits.count > 1 {
                            olderToggle
                            if isShowingOlder { olderSection }
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

    /// 접힌 나머지를 여는 손잡이.
    private var olderToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isShowingOlder.toggle() }
        } label: {
            HStack(spacing: CGFloat(JanjanSpacing.xxs)) {
                Text(isShowingOlder
                     ? t("접기", "Collapse")
                     : olderCountText)
                    .janjanBody(13)
                    .foregroundStyle(Color.ink2)
                Image(systemName: isShowingOlder ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.janjan(.line2))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, CGFloat(JanjanSpacing.xs))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 접힌 줄에 적는 말.
    ///
    /// 무료에게 "지난 기록 9개 더 보기" 라고 적어 놓고 펴면 하나만 읽히는 일이
    /// 없게, 읽히는 수와 잠긴 수를 나눠 적는다(QA 2026-09-21).
    private var olderCountText: String {
        let older = visits.count - 1
        let readable = max(clearIDs.count - 1, 0)
        let locked = older - readable
        if locked > 0, readable > 0 {
            return t("지난 기록 \(readable)개 더 보기 · \(locked)개는 Pro",
                     "\(readable) more · \(locked) in Pro")
        }
        if locked > 0 {
            return t("지난 기록 \(locked)개 (Pro)", "\(locked) earlier visits (Pro)")
        }
        return t("지난 기록 \(older)개 더 보기",
                 older == 1 ? "1 earlier visit" : "\(older) earlier visits")
    }

    /// 한 달치 진료 묶음. 회차를 죽 늘어놓는 것보다 달로 끊어 주면
    /// "8월에 두 번 갔었네" 가 세지 않고도 보인다(사용자 요청 2026-09-21).
    private struct MonthGroup: Identifiable {
        let id: String
        let title: String
        let records: [PrescriptionRecord]
    }

    private var olderGroups: [MonthGroup] {
        let calendar = Calendar.current
        var order: [String] = []
        var buckets: [String: [PrescriptionRecord]] = [:]

        for record in visits.dropFirst() {
            let parts = calendar.dateComponents([.year, .month], from: record.visitDate)
            let key = "\(parts.year ?? 0)-\(parts.month ?? 0)"
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(record)
        }

        // visits 가 최신순이므로 order 도 최신순이고, 묶음 안도 그대로다.
        return order.compactMap { key in
            guard let records = buckets[key], let first = records.first else { return nil }
            return MonthGroup(id: key, title: monthText(first.visitDate), records: records)
        }
    }

    /// 무료에게 선명하게 보이는 회차의 id. Pro 면 전부다.
    private var clearIDs: Set<UUID> {
        guard !pro.isPro else { return Set(visits.map(\.id)) }
        return Set(visits.prefix(Self.freeClearVisits).map(\.id))
    }

    /// 세 회차째부터. 무료에게는 날짜만 남기고 내용이 흐려지며, 누르면 페이월이 열린다.
    ///
    /// **배지는 통틀어 하나뿐이다.** 묶음마다 달았더니 넉 달 다닌 사람의 화면이
    /// 자물쇠 넉 장으로 덮였다(QA 2026-09-21) - 바로 앞에서 용량 변경 카드가
    /// 고친 것과 같은 병이다. 문(탭 → 페이월)은 잠긴 묶음마다 그대로 두고,
    /// 표시만 첫 잠긴 묶음에 남긴다.
    private var olderSection: some View {
        let clear = clearIDs
        let firstLockedGroupID = olderGroups.first { group in
            group.records.contains { !clear.contains($0.id) }
        }?.id

        return VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
            ForEach(olderGroups) { group in
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                    Text(group.title)
                        .janjanBody(12, weight: .medium)
                        .foregroundStyle(Color.muted)
                        .padding(.horizontal, CGFloat(JanjanSpacing.xs))

                    ForEach(group.records.filter { clear.contains($0.id) }) { record in
                        visitCard(record, isBlurred: false)
                    }

                    let locked = group.records.filter { !clear.contains($0.id) }
                    if !locked.isEmpty {
                        VStack(spacing: CGFloat(JanjanSpacing.s)) {
                            ForEach(locked) { record in
                                visitCard(record, isBlurred: true)
                            }
                        }
                        .proGated(.visitHistory, showsBadge: group.id == firstLockedGroupID)
                    }
                }
            }
        }
    }

    /// "2026년 8월" · "August 2026".
    private func monthText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: lang.localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: date)
    }

    // MARK: - 카드

    private var emptyCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                Text(t("아직 진료 기록이 없어요", "No visit records yet"))
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)
                Text(t(
                    "약 탭의 \"진료 기록하기\" 로 남긴 진료가 여기 회차별로 쌓여요.",
                    "Visits you log with \"Log a visit\" on the Meds tab stack up here."
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
                    // 잠긴 카드의 우상단은 비워 둔다 - proGated 의 Pro 배지가
                    // 그 모서리에 얹히므로 칩과 겹친다(QA 2026-09-19).
                    // 흐린 카드에서는 칩이 아래 흐린 내용으로 내려간다.
                    if !isBlurred, record.daysSupplied > 0 {
                        PillChip(text: t("\(record.daysSupplied)일치", "\(record.daysSupplied) days"))
                    }
                }

                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                    if isBlurred, record.daysSupplied > 0 {
                        PillChip(text: t("\(record.daysSupplied)일치", "\(record.daysSupplied) days"))
                    }
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
