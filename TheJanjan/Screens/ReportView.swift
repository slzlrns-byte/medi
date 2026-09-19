import StoreKit
import SwiftUI
import SwiftData
import JanjanCore

/// 리포트 — 진료 준비 (설계 03절).
///
/// 지난 진료 이후(진료 기록이 없으면 4주)의 복약률과 약별 잔여를 보여 주고,
/// 같은 내용을 PDF 한 장으로 낸다. 무엇을 적을지는 `ReportComposer` 가 정한다 —
/// 화면과 PDF 가 다른 말을 하지 않도록.
struct ReportView: View {

    @EnvironmentObject private var pro: ProStore
    @Environment(\.requestReview) private var requestReview

    @Query private var medicationRecords: [MedicationRecord]
    @Query private var scheduleRecords: [ScheduleRecord]
    @Query private var doseRecords: [DoseEventRecord]
    @Query private var stockRecords: [StockEventRecord]
    @Query private var checkInRecords: [CheckInRecord]
    @Query private var symptomRecords: [SymptomEntryRecord]
    @Query(sort: \MedicationNoteRecord.createdAt) private var noteRecords: [MedicationNoteRecord]
    @Query private var doseChangeRecords: [DoseChangeRecord]
    @Query(sort: \PrescriptionRecord.visitDate, order: .reverse)
    private var prescriptionRecords: [PrescriptionRecord]

    /// 진료 전에 적어 두는 메모. 이 기기에만 남는다.
    /// 전체 삭제가 이 키를 지워야 해서 이름을 밖에서도 부를 수 있게 둔다.
    static let questionsDefaultsKey = "janjan.report.questions"

    @AppStorage(ReportView.questionsDefaultsKey) private var questions = ""

    @State private var exportURL: ExportedFile?
    @State private var isExporting = false
    /// 질문 칸의 키보드를 "완료" 로 내리기 위한 초점(사용자 요청 2026-09-19).
    @FocusState private var isEditingQuestions: Bool

    private struct ExportedFile: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    private var today: Date { Date() }

    /// 약 이름 가리기가 실제로 적용되는지. Pro 가 아니면 켜져 있어도 아무 일도 하지 않는다.
    /// PDF 내보내기 내용에는 적용하지 않는다 — 진료실에서 보여 줄 종이라서 이름이 그대로 실린다.
    private var masksNames: Bool { pro.isPro && JanjanPrivacy.hidesNames }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
                    adherenceCard
                    MonthWaveCard(checkIns: checkIns)
                    // 패턴 보기는 Pro. 무료에서는 흐린 그림 위에 자물쇠가 얹힌다.
                    PatternCard(timeline: patternTimeline, isLocked: !pro.isPro)
                        .proGated(.patternView)
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
            .navigationTitle(t("진료 준비", "Visit prep"))
            .sheet(item: $exportURL) { file in
                ShareSheet(items: [file.url])
                    .onDisappear {
                        // 공유가 끝나면 기기에 남겨 두지 않는다. 사용자가 보낸 곳에는
                        // 사본이 남고, 여기 남은 것은 아무도 쓰지 않는 사본일 뿐이다.
                        ReportPDF.removeExportedFiles()
                    }
            }
            .onAppear(perform: maybeAskForReview)
        }
    }

    // MARK: - 리뷰 요청

    /// 평생 한 번, 서로 다른 14일 이상 기록한 사람이 리포트를 열었을 때만
    /// 시스템 리뷰 창을 청한다(심사 체크리스트 4.9). 시스템이 또 거르므로
    /// 실제로는 더 드물게 뜬다. 조르지 않는다 - 조건을 못 채우면 영영 안 뜬다.
    private static let reviewAskedKey = "janjan.review.asked"

    private func maybeAskForReview() {
        #if DEBUG
        // 화면 찍기가 예시 기록(14일 이상)으로 리포트를 여는 순간 시스템 리뷰
        // 창이 떠서 탭바를 덮는다(런 35). 예시 기록 실행에서는 청하지 않는다.
        if ProcessInfo.processInfo.arguments.contains("-JanjanSeedDemoData") { return }
        #endif
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.reviewAskedKey) else { return }
        let calendar = Calendar.current
        let recordedDays = Set(doseRecords.map { calendar.startOfDay(for: $0.core.effectiveDate) })
        guard recordedDays.count >= 14 else { return }
        defaults.set(true, forKey: Self.reviewAskedKey)
        requestReview()
    }

    // MARK: - 데이터

    private var medications: [Medication] { medicationRecords.map { $0.core.displayReady } }
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

    /// 가장 최근에 다녀온 진료. 요약 기간의 시작점이 된다 — 의사가 궁금한 것은
    /// 지난 4주가 아니라 마지막으로 본 뒤의 일이다(강점 결정서 1위).
    /// 오늘 탭에서 일정만 잡은 기록(약·처방일수·메모 없음)은 실제 진료가 아니라
    /// 여기서 세지 않는다(QA 2026-09-19).
    private var lastVisit: Date? {
        prescriptionRecords
            .filter { !($0.medicationIDValues.isEmpty && $0.daysSupplied == 0 && $0.clinicNote.isEmpty) }
            .map(\.core.visitDate)
            .filter { $0 <= today }
            .max()
    }

    /// 화면과 PDF 가 같은 창을 본다. 계산은 ReportComposer 한 곳이 한다.
    private var reportWindow: (start: Date, anchoredToVisit: Bool) {
        ReportComposer.window(endingAt: today, lastVisit: lastVisit)
    }

    private var overallAdherence: Decimal? {
        InventoryCalculator.adherenceRate(
            doseEvents: doses,
            from: reportWindow.start,
            to: today
        )
    }

    private var activeMedications: [Medication] {
        medications.filter { $0.status == .active }
    }

    /// 패턴 보기의 원자료. 계산은 JanjanCore 가 한다 - 화면은 그리기만.
    private var patternTimeline: PatternTimeline {
        PatternTimeline.make(
            dayCount: 28,
            endingAt: today,
            checkIns: checkIns,
            schedules: schedules,
            medications: medications,
            doseEvents: doses
        )
    }

    // MARK: - 조각

    private var adherenceCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text(reportWindow.anchoredToVisit ? t("지난 진료 이후", "Since your last visit") : t("지난 4주", "Past 4 weeks"))
                    .janjanBody(13, weight: .medium)
                    .foregroundStyle(Color.muted)

                if let rate = overallAdherence {
                    let percent = DecimalQuantity.floorToInt(rate * 100)
                    Text(t("복약률 \(percent)%", "Adherence \(percent)%"))
                        .janjanDisplay(30)
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                    adherenceBar(fraction: (rate as NSDecimalNumber).doubleValue)
                } else {
                    Text(t("아직 셀 기록이 없어요.", "No counted records yet."))
                        .janjanBody(15)
                        .foregroundStyle(Color.muted)
                }

                Text(t("건너뜀도 정상적인 선택으로 함께 셉니다.", "Skipped doses are counted too, as a normal choice."))
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
                Text(t("약별 남은 개수", "Remaining per medication"))
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)

                if activeMedications.isEmpty {
                    Text(t("등록된 약이 없어요.", "No medications added yet."))
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
            MaskedNameText(name: medication.displayTitle, isMasked: masksNames)
                .janjanBody(15)
                .foregroundStyle(Color.ink2)
            Spacer()
            // 한 번도 세지 않았으면 0정이라고 말하지 않는다.
            Text(counted
                ? t("\(DecimalQuantity.display(remaining))정", pillsEn(remaining))
                : t("재고 미기록", "Stock not tracked"))
                .janjanBody(15, weight: counted ? .medium : .light)
                .foregroundStyle(counted ? Color.ink : Color.muted)
                .monospacedDigit()
        }
    }

    /// 내보내기는 무료다 (2026-09-10, 강점 결정서 반영). 진료실 준비 노트가 이 앱의
    /// 자리인데 그 한 장을 잠그면 자리 자체를 잠그는 셈이다.
    private var exportCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.s)) {
                Text(t("진료에 가져가기", "Bring to your visit"))
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)

                WhitePillButton(title: t("PDF 로 내보내기", "Export as PDF"), systemImage: "square.and.arrow.up") {
                    export()
                }
                .overlay(
                    Capsule(style: .continuous).strokeBorder(Color.hairline, lineWidth: 1)
                )
                // 만드는 동안은 눌리지 않는다는 것이 눈에도 보여야 한다.
                .opacity(isExporting ? 0.4 : 1)
                .disabled(isExporting)

                Text(t(
                    "만들어진 파일은 사용자가 직접 공유할 때만 기기 밖으로 나갑니다.",
                    "The file leaves this device only when you share it yourself."
                ))
                    .janjanBody(12)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var askDoctorCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text(t("의사에게 물어볼 것", "Questions for my doctor"))
                    .janjanDisplay(20)
                    .foregroundStyle(Color.ink)

                TextEditor(text: $questions)
                    .focused($isEditingQuestions)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button(t("완료", "Done")) { isEditingQuestions = false }
                                .foregroundStyle(Color.ink)
                        }
                    }
                    .janjanBody(14)
                    .foregroundStyle(Color.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 92)
                    .overlay(alignment: .topLeading) {
                        if questions.isEmpty {
                            Text(t(
                                "한 줄에 하나씩 적어 두면 리포트에 함께 나가요.",
                                "One per line — these go out with the report."
                            ))
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

                Text(t(
                    "이 메모는 이 기기에만 남고 iCloud 로 넘어가지 않아요.",
                    "This note stays on this device and does not sync to iCloud."
                ))
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
            doseChanges: doseChangeRecords.map(\.core),
            lastVisit: lastVisit,
            // 다음 진료 기준 "N일 모자랍니다" 는 소진 예측(Pro)과 같은 계산이다.
            // PDF 가 무료가 되면서 이 줄이 유료 기능의 뒷문이 되지 않게,
            // 무료에서는 진료일을 넘기지 않아 부족 캡션 자체가 생기지 않는다.
            nextVisit: pro.isPro ? nextVisit : nil,
            questionsKo: questions,
            language: JanjanLanguage.current
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
