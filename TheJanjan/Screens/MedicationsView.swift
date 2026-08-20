import SwiftUI
import SwiftData
import JanjanCore

/// 약 — 처방·재고 관리 (설계 03절).
///
/// 한 줄에 이름·용량 알약칩·용도 한 줄·잔여 개수. 잔여는 저장된 값이 아니라
/// InventoryCalculator 가 사건에서 매번 다시 계산한 값이다.
struct MedicationsView: View {

    @Environment(\.modelContext) private var context

    @Query(sort: \MedicationRecord.createdAt) private var medicationRecords: [MedicationRecord]
    @Query private var scheduleRecords: [ScheduleRecord]
    @Query private var doseRecords: [DoseEventRecord]
    @Query private var stockRecords: [StockEventRecord]
    @Query(sort: \PrescriptionRecord.visitDate, order: .reverse)
    private var prescriptionRecords: [PrescriptionRecord]

    @State private var isShowingAddFlow = false
    @State private var isShowingPrescription = false
    @State private var pendingDeletion: Row?

    private var today: Date { Date() }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: CGFloat(JanjanSpacing.s)) {
                    prescriptionCard
                    if sections.isEmpty {
                        emptyCard
                    }
                    ForEach(sections, id: \.title) { section in
                        sectionHeader(section.title)
                        ForEach(section.rows) { row in
                            medicationRow(row)
                        }
                    }
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.bottom, CGFloat(JanjanSpacing.xxl))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle("약")
            .navigationBarTitleDisplayMode(.large)
            .overlay(alignment: .bottomTrailing) {
                BlackCircleButton(systemImage: "plus", accessibilityLabelKo: "약 추가") {
                    isShowingAddFlow = true
                }
                .padding(CGFloat(JanjanSpacing.l))
            }
            .sheet(isPresented: $isShowingAddFlow) {
                AddMedicationEntryView()
            }
            .sheet(isPresented: $isShowingPrescription) {
                NavigationStack {
                    PrescriptionFormView { isShowingPrescription = false }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("닫기") { isShowingPrescription = false }
                                    .foregroundStyle(Color.ink)
                            }
                        }
                }
            }
            .confirmationDialog(
                "이 약의 기록을 모두 지울까요?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    // 바깥을 눌러 닫았을 때도 고른 줄을 놓아 준다.
                    // .constant 로 두면 한 번 닫힌 뒤 다시는 열리지 않는다.
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { row in
                Button("삭제", role: .destructive) { delete(row) }
                Button("취소", role: .cancel) { pendingDeletion = nil }
            } message: { row in
                Text("\(row.medication.name) 의 복용 기록과 재고 기록이 함께 사라져요. 되돌릴 수 없어요.")
            }
        }
    }

    // MARK: - 데이터

    struct Row: Identifiable {
        let id: UUID
        let medication: Medication
        let snapshot: InventoryCalculator.Snapshot
        /// 재고를 한 번도 세지 않았으면 잔여를 숫자로 말하지 않는다.
        let hasStock: Bool
    }

    private struct RowGroup {
        let title: String
        let rows: [Row]
    }

    private var medications: [Medication] { medicationRecords.map(\.core) }
    private var schedules: [Schedule] { scheduleRecords.map(\.core) }
    private var doseEvents: [DoseEvent] { doseRecords.map(\.core) }
    private var stockEvents: [StockEvent] { stockRecords.map(\.core) }

    /// 가장 가까운 다음 진료. 부족 판단의 기준선이다.
    private var nextVisit: Date? {
        prescriptionRecords
            .compactMap { $0.core.nextVisitDate }
            .filter { $0 >= today }
            .min()
    }

    private var rows: [Row] {
        let stock = stockEvents
        let doses = doseEvents
        let visit = nextVisit

        return medications.map { medication in
            Row(
                id: medication.id,
                medication: medication,
                snapshot: InventoryCalculator.snapshot(
                    medicationID: medication.id,
                    schedules: schedules,
                    stockEvents: stock,
                    doseEvents: doses,
                    nextVisit: visit,
                    asOf: today
                ),
                hasStock: stock.contains { $0.medicationID == medication.id }
            )
        }
    }

    private var sections: [RowGroup] {
        let all = rows
        return [
            RowGroup(title: "복용 중", rows: all.filter {
                $0.medication.status == .active && $0.medication.kind == .scheduled
            }),
            RowGroup(title: "필요시", rows: all.filter {
                $0.medication.status == .active && $0.medication.kind == .asNeeded
            }),
            RowGroup(title: "중단", rows: all.filter { $0.medication.status == .stopped })
        ]
        .filter { !$0.rows.isEmpty }
    }

    // MARK: - 조각

    /// 다음 진료와 처방 기록 입구.
    ///
    /// 검은 원 버튼은 화면당 하나(약 추가)라서 여기서는 흰 알약을 쓴다(설계 02절).
    private var prescriptionCard: some View {
        JanjanCard(padding: CGFloat(JanjanSpacing.m)) {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                    Text(nextVisitText)
                        .font(JanjanFont.body(15, weight: .medium))
                        .foregroundStyle(Color.ink)
                    Spacer(minLength: 0)
                }

                Text(nextVisit == nil
                     ? "진료일과 받아 온 개수를 적어 두면 소진 예측이 켜져요."
                     : "다음 진료 전에 모자라는 약이 있으면 약 줄에 함께 보여요.")
                    .font(JanjanFont.body(12))
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)

                WhitePillButton(title: "처방 기록하기", systemImage: "doc.text") {
                    isShowingPrescription = true
                }
                .overlay(
                    Capsule(style: .continuous).strokeBorder(Color.hairline, lineWidth: 1)
                )
            }
        }
        .padding(.top, CGFloat(JanjanSpacing.s))
    }

    private var nextVisitText: String {
        guard let nextVisit else { return "다음 진료 미정" }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: today),
            to: Calendar.current.startOfDay(for: nextVisit)
        ).day ?? 0
        return days == 0 ? "오늘 진료" : "다음 진료 D-\(days)"
    }

    private var emptyCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text("첫 약을 등록해 볼까요")
                    .font(JanjanFont.display(20))
                    .foregroundStyle(Color.ink)
                Text("오른쪽 아래 + 를 누르면 이름과 시간만으로 시작할 수 있어요.")
                    .font(JanjanFont.body(13))
                    .foregroundStyle(Color.muted)
            }
        }
        .padding(.top, CGFloat(JanjanSpacing.s))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(JanjanFont.body(13, weight: .medium))
            .foregroundStyle(Color.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, CGFloat(JanjanSpacing.s))
            .padding(.horizontal, CGFloat(JanjanSpacing.xxs))
    }

    private func medicationRow(_ row: Row) -> some View {
        JanjanCard(padding: CGFloat(JanjanSpacing.m)) {
            HStack(alignment: .top, spacing: CGFloat(JanjanSpacing.s)) {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xxs)) {
                    HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                        Text(row.medication.name)
                            .font(JanjanFont.body(16, weight: .medium))
                            .foregroundStyle(Color.ink)
                        if !row.medication.strengthText.isEmpty {
                            PillChip(text: row.medication.strengthText)
                        }
                    }
                    if !row.medication.purposeLine.isEmpty {
                        Text(row.medication.purposeLine)
                            .font(JanjanFont.body(13))
                            .foregroundStyle(Color.muted)
                    }
                }

                Spacer(minLength: CGFloat(JanjanSpacing.xs))

                VStack(alignment: .trailing, spacing: 2) {
                    if row.hasStock {
                        Text("\(DecimalQuantity.display(row.snapshot.remaining))정")
                            .font(JanjanFont.display(20))
                            .foregroundStyle(Color.ink)
                            .monospacedDigit()
                    } else {
                        Text("재고 미기록")
                            .font(JanjanFont.body(13))
                            .foregroundStyle(Color.muted)
                    }
                    if let text = runOutText(row) {
                        Text(text)
                            .font(JanjanFont.body(12))
                            .foregroundStyle(Color.muted)
                    }
                }
            }
        }
        .contextMenu {
            if row.medication.status == .active {
                Button("복용 중단") {
                    MedicationStore.setStatus(.stopped, for: row.id, in: context)
                    rescheduleReminders()
                }
            } else {
                Button("다시 복용") {
                    MedicationStore.setStatus(.active, for: row.id, in: context)
                    rescheduleReminders()
                }
            }
            Button("삭제", role: .destructive) { pendingDeletion = row }
        }
    }

    private func runOutText(_ row: Row) -> String? {
        guard row.hasStock else { return nil }
        if let shortfall = row.snapshot.shortfallDays, shortfall > 0 {
            return "진료 전 \(shortfall)일 모자람"
        }
        guard let days = row.snapshot.daysRemaining else { return nil }
        let whole = DecimalQuantity.floorToInt(days)
        guard whole >= 0 else { return nil }
        return "약 \(whole)일치"
    }

    // MARK: - 손대기

    private func delete(_ row: Row) {
        MedicationStore.delete(medicationID: row.id, in: context)
        pendingDeletion = nil
        rescheduleReminders()
    }

    private func rescheduleReminders() {
        Task { await ReminderPlanner.reschedule(using: context) }
    }
}

/// 약 추가의 첫 갈림길. 직접 입력은 무료, 약봉투 스캔은 Pro다(유도 세 곳 중 하나).
private struct AddMedicationEntryView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingForm = false
    @State private var isShowingScan = false

    var body: some View {
        NavigationStack {
            VStack(spacing: CGFloat(JanjanSpacing.s)) {
                entryRow(
                    title: "직접 입력",
                    subtitle: "이름 · 용량 · 시간을 하나씩 적어요.",
                    systemImage: "square.and.pencil"
                ) {
                    isShowingForm = true
                }

                entryRow(
                    title: ProFeature.pharmacyScan.titleKo,
                    subtitle: "봉투 사진에서 약 이름을 읽어 와요. 사진은 저장되지 않아요.",
                    systemImage: "camera"
                ) {
                    isShowingScan = true
                }
                .proGated(.pharmacyScan)

                Spacer()
            }
            .padding(.horizontal, CGFloat(JanjanSpacing.m))
            .padding(.top, CGFloat(JanjanSpacing.m))
            .fogBackground()
            .navigationTitle("약 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(Color.ink)
                }
            }
            .navigationDestination(isPresented: $isShowingForm) {
                MedicationFormView { dismiss() }
            }
            .navigationDestination(isPresented: $isShowingScan) {
                PharmacyScanView { dismiss() }
            }
        }
    }

    private func entryRow(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            JanjanCard(padding: CGFloat(JanjanSpacing.m)) {
                HStack(spacing: CGFloat(JanjanSpacing.s)) {
                    CircleGlyph(systemImage: systemImage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(JanjanFont.body(16, weight: .medium))
                            .foregroundStyle(Color.ink)
                        Text(subtitle)
                            .font(JanjanFont.body(12))
                            .foregroundStyle(Color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: CGFloat(JanjanSpacing.xs))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MedicationsView()
        .modelContainer(for: JanjanSchema.allModels, inMemory: true)
        .environmentObject(ProStore())
}
