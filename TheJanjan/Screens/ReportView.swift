import SwiftUI
import JanjanCore

/// 리포트 — 진료 준비 (설계 03절).
///
/// 골격에서는 지난 4주 복약률과 약별 잔여만 보여 준다.
/// 추이선·PDF·CSV 는 Pro 범위이고 다음 단계에서 붙인다.
struct ReportView: View {

    private let today = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.m)) {
                    adherenceCard
                    perMedicationCard
                    askDoctorCard
                    MedicalDisclaimer()
                        .padding(.horizontal, CGFloat(JanjanSpacing.xxs))
                }
                .padding(.horizontal, CGFloat(JanjanSpacing.m))
                .padding(.bottom, CGFloat(JanjanSpacing.xxl))
            }
            .fogBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle("리포트")
        }
    }

    // MARK: - 데이터

    private var doses: [DoseEvent] { SampleData.doseEvents(referenceDate: today) }
    private var stock: [StockEvent] { SampleData.stockEvents(referenceDate: today) }

    private var overallAdherence: Decimal? {
        InventoryCalculator.adherenceRate(
            doseEvents: doses,
            last28DaysEndingAt: today
        )
    }

    // MARK: - 조각

    private var adherenceCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text("지난 4주")
                    .font(JanjanFont.body(13, weight: .medium))
                    .foregroundStyle(Color.muted)

                if let rate = overallAdherence {
                    let percent = DecimalQuantity.floorToInt(rate * 100)
                    Text("복약률 \(percent)%")
                        .font(JanjanFont.display(30))
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                    adherenceBar(fraction: (rate as NSDecimalNumber).doubleValue)
                } else {
                    Text("아직 셀 기록이 없어요.")
                        .font(JanjanFont.body(15))
                        .foregroundStyle(Color.muted)
                }

                Text("건너뜀도 정상적인 선택으로 함께 셉니다.")
                    .font(JanjanFont.body(12))
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
                    .font(JanjanFont.display(20))
                    .foregroundStyle(Color.ink)

                ForEach(SampleData.medications) { medication in
                    let remaining = InventoryCalculator.remaining(
                        for: medication.id,
                        stockEvents: stock,
                        doseEvents: doses,
                        asOf: today
                    )
                    HStack {
                        Text(medication.displayTitle)
                            .font(JanjanFont.body(15))
                            .foregroundStyle(Color.ink2)
                        Spacer()
                        Text("\(DecimalQuantity.display(remaining))정")
                            .font(JanjanFont.body(15, weight: .medium))
                            .foregroundStyle(Color.ink)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var askDoctorCard: some View {
        JanjanCard {
            VStack(alignment: .leading, spacing: CGFloat(JanjanSpacing.xs)) {
                Text("의사에게 물어볼 것")
                    .font(JanjanFont.display(20))
                    .foregroundStyle(Color.ink)
                Text("진료 전에 여기 적어 두면 리포트에 함께 나갑니다.")
                    .font(JanjanFont.body(13))
                    .foregroundStyle(Color.muted)
            }
        }
    }
}

#Preview {
    ReportView()
}
