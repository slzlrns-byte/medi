import Foundation
import OSLog
import SwiftData
import JanjanCore

/// 답 없이 지나간 시간대를 미기록으로 채운다 (2026-09-19 결정).
///
/// **왜 필요한가.** 복약률의 분모는 저장된 사건의 개수다. 그런데 사건은
/// 사용자가 답할 때만 생겼다 - 앱을 안 연 날은 통째로 통계에서 사라졌다.
/// 28일 중 14일만 열어 그때마다 "복용함" 을 눌렀다면 복약률이 100% 로 찍힌다.
/// 앱을 덜 여는 사람일수록, 그러니까 실제로 더 많이 빠트리는 사람일수록
/// 숫자가 더 좋게 나오는 역설이었고, 그 숫자가 진료실로 나갔다.
///
/// 지키는 것 셋.
///
/// · **채우는 것은 답이 아니다.** 출처를 `.automatic` 으로 남겨,
///   "기록 없이 지나간 시간대" 가 이 줄들을 계속 물어본다. 사용자가 그
///   자리에서 답하면 `DoseRecorder` 가 같은 줄을 고쳐 쓰고 출처가 바뀌며,
///   그때부터 다시 묻지 않는다.
/// · **오늘은 채우지 않는다.** 오늘 저녁 약은 아직 빠트린 것이 아니다.
/// · **재고는 건드리지 않는다.** 미기록은 재고를 빼지 않는다(설계 05절의
///   "복용함만 뺀다"). 채워도 남은 개수는 그대로다.
@MainActor
enum UnrecordedBackfill {

    private static let logger = Logger(subsystem: Janjan.appBundleID, category: "backfill")

    /// 마지막으로 훑은 날. 하루에 한 번이면 족하다.
    private static let lastRunKey = "janjan.backfill.lastRunDay"

    /// 한 번 훑고 비어 있던 자리를 채운다. 여러 번 불러도 결과가 같다 -
    /// 이미 사건이 있는 자리는 건너뛴다.
    /// - Parameter force: 날이 같아도 다시 훑는다. 테스트와 "이 자리에서
    ///   당장 맞춰야 하는" 경로만 쓴다.
    @discardableResult
    static func run(
        in context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current,
        force: Bool = false
    ) -> Int {

        // 훑는 비용은 31일 × 기록 전체다. 앱을 여닫을 때마다 반복하면
        // 한 해치가 쌓인 기기에서 앞으로 나올 때마다 눈에 띄게 걸린다.
        // 채울 것은 하루에 한 번만 생기므로 하루에 한 번만 훑는다.
        let endDayStart = calendar.startOfDay(for: now)
        let defaults = UserDefaults.standard
        if !force,
           let last = defaults.object(forKey: lastRunKey) as? Date,
           calendar.isDate(last, inSameDayAs: endDayStart) {
            return 0
        }
        defaults.set(endDayStart, forKey: lastRunKey)

        let medications = fetch(MedicationRecord.self, in: context).map { $0.core.displayReady }
        guard !medications.isEmpty else { return 0 }

        let schedules = fetch(ScheduleRecord.self, in: context).map(\.core)
        guard !schedules.isEmpty else { return 0 }

        let doseEvents = fetch(DoseEventRecord.self, in: context).map(\.core)

        // 화면이 들여다보는 범위와 같은 상한을 쓴다. 이보다 오래된 것은
        // 되돌아볼 자리도 없으므로 채워 봐야 말을 걸지 못한다.
        let endDay = endDayStart
        guard let from = calendar.date(
            byAdding: .day, value: -(UnrecordedSlots.maxLookbackDays - 1), to: endDay
        ) else { return 0 }

        let lines = UnrecordedSlots.find(
            from: from,
            until: endDay,
            schedules: schedules,
            medications: medications,
            doseEvents: doseEvents,
            calendar: calendar
        )

        var filled = 0
        for line in lines {
            // 이미 채워 둔 줄(`.automatic`)은 여기 다시 올라오지만 건드리지
            // 않는다. 정말 비어 있는 자리만 채운다.
            for entry in line.entries where entry.status == nil {
                DoseRecorder.record(
                    medicationID: entry.medicationID,
                    slotKey: line.slot.storageKey,
                    status: .unrecorded,
                    source: .automatic,
                    on: line.day,
                    at: line.plannedAt,
                    quantity: entry.dose,
                    in: context,
                    calendar: calendar
                )
                filled += 1
            }
        }

        guard filled > 0 else { return 0 }
        do {
            try context.save()
        } catch {
            logger.error("미기록 채우기 저장 실패: \(error.localizedDescription, privacy: .public)")
            return 0
        }
        return filled
    }

    private static func fetch<T: PersistentModel>(_ model: T.Type, in context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }
}
