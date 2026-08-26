import SwiftUI
import SwiftData
import JanjanCore

/// 리포트 — 진료 준비 (설계 03절).
///
/// 지난 4주 복약률과 약별 잔여를 보여 주고, 같은 내용을 PDF 한 장으로 낸다.
/// 무엇을 적을지는 `ReportComposer` 가 정한다 — 화면과 PDF 가 다른 말을 하지 않도록.
struct ReportView: View {

    @Query private var medicationRecords: [MedicationRecord]
    @Query private var scheduleRecords: [ScheduleRecord]
    @Query private var doseRecords: [DoseEventRecord]
    @Query private var stockRecords: [StockEventRecord]
    @Query private var checkInRecords: [CheckInRecord]
    @Query private var symptomRecords: [SymptomEntryRecord]
    @Query(sort: \MedicationNoteRecord.createdAt) private var noteRecords: [MedicationNoteRecord]
    @Query(sort: \PrescriptionRecord.visitDate, order: .reverse)
    private var prescriptionRecords: [PrescriptionRecord]

    /// 진료 전에 적어 두는 메모. 이 기기에만 남는다.
    /// 전체 삭제가 이 키를 지워야 해서 이름을 밖에서도 부를 수 있게 둔다.
    static let questionsDefaultsKey = "janjan.report.questions"

    @AppStorage(ReportView.questionsDefaultsKey) private var questions = ""

    @State private var exportURL: ExportedFile?
    @State private var isExporting = false

    private struct ExportedFile: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    private var today: Date { Date() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
                    adherenceCard
                    perMedicationCard
                    askDoctorCard
                    exportCard
                    MedicalDisclaimer()
                        .padding(.horizontal, CGFloat(JanjanSpacing.xxs))
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.bottom, CGFloat(JanjanSpacing.xxl))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle("리포트")
            .sheet(item: $exportURL) { file in
                ShareSheet(items: [file.url])
                    .onDisappear {
                        // 공유가 끝나면 기기에 남겨 두지 않는다. 사용자가 보낸 곳에는
                        // 사본이 남고, 여기 남은 것은 아무도 쓰지 않는 사본일 뿐이다.
                        ReportPDF.removeExportedFiles()
                    }
            }
        }
    }

    // MARK: - 데이터

    private var medications: [Medication] { medicationRecords.map(\.core) }
    private var schedules: [Schedule] { scheduleRecords.map(\.core) }
    private var doses: [DoseEvent] { doseRecords.map(\.core) }
    private var stock: [StockEvent] { stockRecords.map(\.core) }
    private var checkIns: [CheckIn] { checkInRecords.map(\.core) }
    private var symptomEntries: [SymptomEntry] { symptomRecords.map(\.core) }
    private var medicationNotes: [MedicationNote] { noteRecords.map(\.core) }

    private var nextVisit: Date? {
        prescriptionRecords
            .compactMap { $0.core.nextVisitDate }
            .filter { $0 >= today }
            .min()
    }

    private var overallAdherence: Decimal? {
        InventoryCalculator.adherenceRate(
            doseEvents: doses,
            last28DaysEndingAt: today
        )
    }

    private var activeMedications: [Medication] {
        medications.filter { $0.status == .active }
    }

    // MARK: - 조각

    private var adherenceCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text("지난 4주")
                    .janjanBody(13, weight: .medium)
                    .foregroundStyle(Color.muted)

                if let rate = overallAdherence {
                    let percent = DecimalQuantity.floorToInt(rate * 100)
                    Text("복약률 \(percent)%")
                        .janjanDisplay(30)
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                    adherenceBar(fraction: (rate as NSDecimalNumber).doubleValue)
                } else {
                    Text("아직 셀 기록이 없어요.")
                        .janjanBody(15)
                        .foregroundStyle(Color.muted)
                }

                Text("건너뜀도 정상적인 선택으로 함께 셉니다.")
                    .janjanBody(12)
                    .foregroundStyle(Color.muted)
                    .padding(.top, CGFloat(JanjanSpacing.xxs))
            }
        }
    }

    /// 둥근 막대. 끝 반지름 = 굵기 / 2 (설계 02절).
    private func adherenceBar(fraction: Double) -> some View {
        GeometryReader { geometry in
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.janjan(.surface2))
                Capsule(style: .continuous)
                    .fill(Color.janjan(.sage))
                    .frame(width: geometry.size.width * clamped)
            }
        }
        .frame(height: 14)
        .padding(.top, CGFloat(JanjanSpacing.xxs))
    }

    private var perMedicationCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("약별 남은 개수")
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)

                if activeMedications.isEmpty {
                    Text("등록된 약이 없어요.")
                        .janjanBody(13)
                        .foregroundStyle(Color.muted)
                }

                ForEach(activeMedications) { medication in
                    medicationLine(medication)
                }
            }
        }
    }

    private func medicationLine(_ medication: Medication) -> some View {
        let counted = stock.contains { $0.medicationID == medication.id }
        let remaining = InventoryCalculator.remaining(
            for: medication.id,
            stockEvents: stock,
            doseEvents: doses,
            asOf: today
        )

        return HStack {
            Text(medication.displayTitle)
                .janjanBody(15)
                .foregroundStyle(Color.ink2)
            Spacer()
            // 한 번도 세지 않았으면 0정이라고 말하지 않는다.
            Text(counted ? "\(DecimalQuantity.display(remaining))정" : "재고 미기록")
                .janjanBody(15, weight: counted ? .medium : .light)
                .foregroundStyle(counted ? Color.ink : Color.muted)
                .monospacedDigit()
        }
    }

    /// 내보내기는 Pro. 무료 사용자가 누르면 페이월이 올라온다(유도 세 곳 중 하나).
    private var exportCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text("진료에 가져가기")
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)

                WhitePillButton(title: "PDF 로 내보내기", systemImage: "square.and.arrow.up") {
                    export()
                }
                .overlay(
                    Capsule(style: .continuous).strokeBorder(Color.hairline, lineWidth: 1)
                )
                .proGated(.reports)
                .disabled(isExporting)

                Text("만들어진 파일은 사용자가 직접 공유할 때만 기기 밖으로 나갑니다.")
                    .janjanBody(12)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var askDoctorCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text("의사에게 물어볼 것")
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)

                TextEditor(text: $questions)
                    .janjanBody(14)
                    .foregroundStyle(Color.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 92)
                    .overlay(alignment: .topLeading) {
                        if questions.isEmpty {
                            Text("한 줄에 하나씩 적어 두면 리포트에 함께 나가요.")
                                .janjanBody(14)
                                .foregroundStyle(Color.muted)
                                .allowsHitTesting(false)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                    }
                    // 바탕이 없으면 글자만 떠 있어 입력칸으로 보이지 않고,
                    // TextEditor 의 안쪽 여백 때문에 위 제목과 어긋나 보인다.
                    .padding(CGFloat(JanjanSpacing.xxs))
                    .background(
                        RoundedRectangle(cornerRadius: CGFloat(JanjanRadius.row), style: .continuous)
                            .fill(Color.janjan(.surface2))
                    )

                Text("이 메모는 이 기기에만 남고 iCloud 로 넘어가지 않아요.")
                    .janjanBody(12)
                    .foregroundStyle(Color.muted)
            }
        }
    }

    // MARK: - 내보내기

    private func export() {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }

        let content = ReportComposer.make(
            endingAt: today,
            medications: medications,
            schedules: schedules,
            doseEvents: doses,
            stockEvents: stock,
            checkIns: checkIns,
            medicationNotes: medicationNotes,
            symptomEntries: symptomEntries,
            nextVisit: nextVisit,
            questionsKo: questions
        )

        if let url = ReportPDF.write(content) {
            exportURL = ExportedFile(url: url)
        }
    }
}

#Preview {
    ReportView()
        .modelContainer(for: JanjanSchema.allModels, inMemory: true)
        .environmentObject(ProStore())
}
