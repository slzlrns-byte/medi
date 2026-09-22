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
    /// 내보내기가 실패한 이유. 조용히 끝나면 사용자는 앱이 고장 난 줄 안다.
    @State private var exportError: String?
    /// 무료 내보내기에 붙는 보상형 광고. Pro 면 만들기만 하고 쓰지 않는다.
    @StateObject private var rewarded = RewardedAdLoader()
    /// 광고를 도중에 닫았을 때 조용히 아무 일도 안 일어나면 고장으로 보인다.
    @State private var didSkipAd = false
    @State private var isShowingVisitHistory = false
    /// 질문 칸의 키보드를 "완료" 로 내리기 위한 초점(사용자 요청 2026-09-19).
    @FocusState private var isEditingQuestions: Bool

    private struct ExportedFile: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    /// 자정을 넘기면 값이 바뀌어 화면이 다시 그려진다(JanjanClock).
    @ObservedObject private var clock = JanjanClock.shared
    private var today: Date { clock.today }
    private var endOfToday: Date { clock.endOfToday }

    /// 약 이름 가리기가 켜져 있는지. 켜는 문이 Pro 이고, 한 번 켜면 계속 가린다.
    /// PDF 내보내기 내용에는 적용하지 않는다 — 진료실에서 보여 줄 종이라서 이름이 그대로 실린다.
    private var masksNames: Bool { JanjanPrivacy.hidesNames }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
                    adherenceCard
                    MonthWaveCard(checkIns: checkIns)
                    // 패턴 보기는 Pro. 무료에서는 흐린 그림 위에 자물쇠가 얹힌다.
                    VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                        PatternCard(timeline: patternTimeline, isLocked: !pro.isPro)
                            .proGated(.patternView)
                        // 그림이 처음 생길 만큼 쌓였을 때만. 빈 그림 앞에서
                        // 권하면 무엇을 여는지 알 수 없다.
                        if hasEnoughForPattern {
                            ProMomentNote(moment: .patternReady)
                        }
                    }
                    ChangesSinceVisitCard()
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
            // 질문 칸에서 다른 곳을 누르거나 스크롤하면 키보드가 내려간다.
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(TapGesture().onEnded { isEditingQuestions = false })
            .navigationTitle(t("진료 준비", "Visit prep"))
            .sheet(isPresented: $isShowingVisitHistory) {
                VisitHistoryView()
            }
            .sheet(item: $exportURL) { file in
                ShareSheet(items: [file.url])
                    .onDisappear {
                        // 공유가 끝나면 기기에 남겨 두지 않는다. 사용자가 보낸 곳에는
                        // 사본이 남고, 여기 남은 것은 아무도 쓰지 않는 사본일 뿐이다.
                        ReportPDF.removeExportedFiles()
                    }
            }
            .onAppear {
                maybeAskForReview()
                // 누른 뒤에 받으면 몇 초를 기다리게 된다. Pro 는 부르지 않는다.
                if !pro.isPro { rewarded.preload() }
            }
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
            .filter { !$0.core.isScheduleOnly }
            .map(\.core.visitDate)
            .filter { $0 < endOfToday }
            .max()
    }

    /// 화면과 PDF 가 같은 창을 본다. 계산은 ReportComposer 한 곳이 한다.
    private var reportWindow: (start: Date, anchoredToVisit: Bool) {
        ReportComposer.window(endingAt: today, lastVisit: lastVisit)
    }

    /// **복약률은 받은 약으로 센다**(사용자 결정 2026-09-21).
    /// 종이와 같은 계산을 쓴다 - 한 화면 안에서 두 숫자가 달라지면 안 된다.
    private var adherence: InventoryCalculator.PrescriptionAdherence? {
        InventoryCalculator.prescriptionAdherence(
            prescriptions: prescriptionRecords.map(\.core),
            stockEvents: stock,
            doseEvents: doses,
            medications: medicationRecords.map { $0.core.displayReady },
            asOf: endOfToday
        )
    }

    private var activeMedications: [Medication] {
        medications.filter { $0.status == .active }
    }

    /// 무료에게 패턴 보기를 권할 만큼 기록이 쌓였는지. 최근 4주 중 기분이나
    /// 복약이 기록된 날이 이레는 되어야 그림이 그림처럼 보인다.
    private var hasEnoughForPattern: Bool {
        patternTimeline.days.filter { $0.moodScore != nil || $0.takenFraction != nil }.count
            >= PatternCard.freeClearDays
    }

    /// 패턴 보기의 원자료. 계산은 JanjanCore 가 한다 - 화면은 그리기만.
    private var patternTimeline: PatternTimeline {
        PatternTimeline.make(
            dayCount: 28,
            endingAt: endOfToday,
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
                HStack(alignment: .firstTextBaseline, spacing: CGFloat(JanjanSpacing.xs)) {
                    Text(reportWindow.anchoredToVisit ? t("지난 진료 이후", "Since your last visit") : t("지난 4주", "Past 4 weeks"))
                        .janjanBody(13, weight: .medium)
                        .foregroundStyle(Color.muted)

                    Spacer(minLength: CGFloat(JanjanSpacing.xs))

                    // 이 숫자가 "지난 진료 이후" 라고 적혀 있는데, 정작 그 진료가
                    // 무엇이었는지 보러 갈 길이 약 탭 안에만 있었다
                    // (사용자 요청 2026-09-21). 숫자 옆에 둔다.
                    Button {
                        isShowingVisitHistory = true
                    } label: {
                        HStack(spacing: 3) {
                            Text(t("지난 진료 보기", "Past visits"))
                                .janjanBody(12, weight: .medium)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Color.ink2)
                        .padding(.horizontal, CGFloat(JanjanSpacing.s))
                        .frame(minHeight: 44)
                        .background(Capsule(style: .continuous).fill(Color.janjan(.surface2)))
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if let adherence {
                    let percent = DecimalQuantity.floorToInt(adherence.rate * 100)
                    Text(t("복약률 \(percent)%", "Adherence \(percent)%"))
                        .janjanDisplay(30)
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                    adherenceBar(fraction: (adherence.rate as NSDecimalNumber).doubleValue)
                    // 비율만 두지 않는다 - 무엇으로 잰 숫자인지 같이 적는다.
                    // 종이와 **같은 문장**을 쓴다. 화면만 진료일을 빼 두면 같은
                    // 숫자를 두고 두 곳이 다른 말을 한다(QA 2026-09-21).
                    let visitDay = ReportComposer.monthDayText(
                        adherence.visitDate, language: JanjanLanguage.current
                    )
                    Text(t(
                        "\(visitDay) 진료 · 약 \(adherence.items.count)종 · 지금까지 \(DecimalQuantity.display(adherence.expected))정 예정 중 복용 기록 \(DecimalQuantity.display(adherence.taken))정",
                        "\(visitDay) visit · \(adherence.items.count) medication\(adherence.items.count == 1 ? "" : "s") · \(DecimalQuantity.display(adherence.taken)) of \(DecimalQuantity.display(adherence.expected)) due so far"
                    ))
                        .janjanBody(12)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // 셀 근거가 없으면 숫자를 지어내지 않는다.
                    Text(t("진료와 받아 온 개수를 적어 두면 복약률이 나와요.",
                           "Log a visit and how many pills you received, and adherence appears here."))
                        .janjanBody(15)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(t("약마다 복약률을 내서 평균을 냈어요. 기록하지 않은 복용은 복용한 것으로 세지 않고, 나중에 채워 넣으면 그때 반영돼요.",
                       "Each medication's rate is averaged. A dose you didn't record isn't counted as taken; fill it in later and it counts then."))
                    .janjanBody(12)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
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
            asOf: endOfToday
        )

        return HStack {
            MaskedNameText(name: medication.displayTitle, isMasked: masksNames)
                .janjanBody(15)
                .foregroundStyle(Color.ink2)
            Spacer()
            // 한 번도 세지 않았으면 0정이라고 말하지 않는다. 음수도 적지
            // 않는다 - 약 탭은 0 으로 깎는데 여기만 "-16정" 을 보여 주면
            // 같은 앱이 두 말을 한다(QA 2026-09-21).
            Text(!counted
                 ? t("재고 미기록", "Stock not tracked")
                 : (remaining < 0
                    ? t("확인 필요", "Needs recount")
                    : t("\(DecimalQuantity.display(remaining))정", pillsEn(remaining))))
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

                WhitePillButton(
                    title: pro.isPro
                        ? t("PDF 로 내보내기", "Export as PDF")
                        : t("광고 보고 PDF 받기", "Watch an ad to get the PDF"),
                    systemImage: pro.isPro ? "square.and.arrow.up" : "play.rectangle"
                ) {
                    exportTapped()
                }
                // 만드는 동안은 눌리지 않는다는 것이 눈에도 보여야 한다.
                .opacity(isExporting ? 0.4 : 1)
                .disabled(isExporting)

                // 흐려지는 것만으로는 "멈췄다" 와 구별되지 않는다. 기록이
                // 많으면 그리는 데 한 박자 걸리는데 그동안 아무 말이
                // 없었다(QA 2026-09-21).
                if isExporting {
                    HStack(spacing: CGFloat(JanjanSpacing.xs)) {
                        ProgressView().controlSize(.small).tint(Color.ink2)
                        Text(t("한 장으로 만들고 있어요…", "Putting it on one page…"))
                            .janjanBody(12)
                            .foregroundStyle(Color.ink2)
                    }
                }

                Text(t(
                    "만든 파일은 직접 공유할 때만 기기 밖으로 나가요.",
                    "The file leaves this device only when you share it yourself."
                ))
                    .janjanBody(12)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if let exportError {
                    Text(exportError)
                        .janjanBody(13)
                        .foregroundStyle(Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !pro.isPro {
                    Text(didSkipAd
                         ? t("광고를 끝까지 보면 바로 만들어 드려요. Pro 를 쓰시면 광고 없이 나와요.",
                             "Watch the ad through and it's made right away. With Pro it comes out without one.")
                         : t("내보내기는 무료예요. 짧은 광고를 보면 바로 만들어 드려요.",
                             "Exporting is free — watch a short ad and it's made right away."))
                        .janjanBody(12)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    /// 무료는 광고를 보고 받는다(2026-09-19 광고 도입). 강제로 끼어드는
    /// 전면 광고가 아니라 눌러서 여는 교환이고, 광고를 못 받았으면 그냥
    /// 통과시킨다 - 진료에 들고 갈 종이를 광고 때문에 못 만들게 하지 않는다.
    private func exportTapped() {
        guard !isExporting else { return }
        if pro.isPro {
            export()
        } else {
            didSkipAd = false
            rewarded.show(
                onReward: { export() },
                onSkip: { didSkipAd = true }
            )
        }
    }

    private func export() {
        guard !isExporting else { return }
        isExporting = true
        exportError = nil

        let content = ReportComposer.make(
            endingAt: endOfToday,
            medications: medications,
            schedules: schedules,
            doseEvents: doses,
            stockEvents: stock,
            checkIns: checkIns,
            medicationNotes: medicationNotes,
            symptomEntries: symptomEntries,
            // 용량 변경은 무료 종이에도 그대로 실린다. 한때 잠갔다가
            // 되돌렸다 - 이 줄은 앱이 계산한 것이 아니라 사용자가 직접 적어
            // 둔 글자이고, 광고를 끝까지 보고 받은 종이에서 구역이 조용히
            // 빠지는 것은 교환 조건을 바꾸는 일이다(2026-09-21).
            doseChanges: doseChangeRecords.map(\.core),
            prescriptions: prescriptionRecords.map(\.core),
            lastVisit: lastVisit,
            // 다음 진료 기준 "N일 모자랍니다" 는 소진 예측(Pro)과 같은 계산이다.
            // PDF 가 무료가 되면서 이 줄이 유료 기능의 뒷문이 되지 않게,
            // 무료에서는 진료일을 넘기지 않아 부족 캡션 자체가 생기지 않는다.
            nextVisit: pro.isPro ? nextVisit : nil,
            questionsKo: questions,
            language: JanjanLanguage.current,
            // 주차별 구역도 같은 이유로 Pro 다. 패턴 보기가 파는 것이 이
            // 4주 시계열이라, 무료 종이에 찍어 주면 잠근 문 옆에 문을 하나
            // 더 내는 셈이 된다. 무료에서는 구역 자체가 생기지 않는다 -
            // 종이에 "Pro 에서 열려요" 를 적지는 않는다(진료실에서 본다).
            weeklyBreakdown: pro.isPro
        )

        // 한 박자 넘긴 뒤에 그린다. 동기로 이어 붙이면 isExporting 이 true 인
        // 화면이 한 번도 그려지지 않아, "만드는 중" 표시가 눈에 보이지 않았다
        // (QA 2026-09-19). 기록이 많으면 그 사이 버튼이 눌리는 것처럼 보인다.
        Task { @MainActor in
            defer { isExporting = false }
            guard let url = ReportPDF.write(content) else {
                // 저장 공간이 없을 때가 대부분이다. 광고까지 보고 아무 말도
                // 없이 끝나면 사용자는 앱이 고장 난 줄 안다.
                exportError = t(
                    "PDF 를 만들지 못했어요. 기기에 저장 공간이 남아 있는지 확인하고 다시 시도해 주세요.",
                    "Couldn't make the PDF. Check that your device has free space and try again."
                )
                return
            }
            exportURL = ExportedFile(url: url)
        }
    }
}

#Preview {
    ReportView()
        .modelContainer(for: JanjanSchema.allModels, inMemory: true)
        .environmentObject(ProStore())
}
