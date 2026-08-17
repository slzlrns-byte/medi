import SwiftUI
import JanjanCore

/// 약 — 처방·재고 관리 (설계 03절).
///
/// 한 줄에 이름·용량 알약칩·용도 한 줄·잔여 개수. 잔여는 저장된 값이 아니라
/// InventoryCalculator 가 사건에서 매번 다시 계산한 값이다.
struct MedicationsView: View {

    @State private var isShowingAddFlow = false

    private var today: Date { Date() }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: CGFloat(JanjanSpacing.s)) {
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
        }
    }

    // MARK: - 데이터

    private struct Row: Identifiable {
        let id: UUID
        let medication: Medication
        let snapshot: InventoryCalculator.Snapshot
    }

    private struct RowGroup {
        let title: String
        let rows: [Row]
    }

    private var rows: [Row] {
        let stock = SampleData.stockEvents(referenceDate: today)
        let doses = SampleData.doseEvents(referenceDate: today)
        let nextVisit = SampleData.prescription(referenceDate: today).nextVisitDate

        return SampleData.medications.map { medication in
            Row(
                id: medication.id,
                medication: medication,
                snapshot: InventoryCalculator.snapshot(
                    medicationID: medication.id,
                    schedules: SampleData.schedules,
                    stockEvents: stock,
                    doseEvents: doses,
                    nextVisit: nextVisit,
                    asOf: today
                )
            )
        }
    }

    private var sections: [RowGroup] {
        let all = rows
        return [
            RowGroup(title: "복용 중", rows: all.filter { $0.medication.kind == .scheduled }),
            RowGroup(title: "필요시", rows: all.filter { $0.medication.kind == .asNeeded })
        ]
        .filter { !$0.rows.isEmpty }
    }

    // MARK: - 조각

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
                    Text("\(DecimalQuantity.display(row.snapshot.remaining))정")
                        .font(JanjanFont.display(20))
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                    if let text = runOutText(row) {
                        Text(text)
                            .font(JanjanFont.body(12))
                            .foregroundStyle(Color.muted)
                    }
                }
            }
        }
    }

    private func runOutText(_ row: Row) -> String? {
        guard let days = row.snapshot.daysRemaining else { return nil }
        let whole = DecimalQuantity.floorToInt(days)
        guard whole >= 0 else { return nil }
        if let shortfall = row.snapshot.shortfallDays {
            return "진료 전 \(shortfall)일 모자람"
        }
        return "약 \(whole)일치"
    }
}

/// 약 추가의 첫 갈림길. 직접 입력은 무료, 약봉투 스캔은 Pro다(유도 세 곳 중 하나).
private struct AddMedicationEntryView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: CGFloat(JanjanSpacing.s)) {
                entryRow(
                    title: "직접 입력",
                    subtitle: "이름 · 용량 · 시간을 하나씩 적어요.",
                    systemImage: "square.and.pencil"
                ) {
                    // TODO: 약 등록 폼 (이름 검색 → 용량 → 시간대 → 재고)
                }

                entryRow(
                    title: ProFeature.pharmacyScan.titleKo,
                    subtitle: "봉투 사진에서 약 이름을 읽어 와요. 사진은 저장되지 않아요.",
                    systemImage: "camera"
                ) {
                    // TODO: 온디바이스 Vision 텍스트 인식 → 확인 화면 → 저장
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
        .environmentObject(ProStore())
}
