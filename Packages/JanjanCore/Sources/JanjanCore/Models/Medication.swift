import Foundation

/// 사용자가 등록한 약 하나.
///
/// 용량 변경 이력은 v1 에서 `Prescription` 과 `Schedule` 로만 남기고,
/// 별도 MedicationVersion 엔티티는 v2 로 미룬다(설계 13절).
public struct Medication: Identifiable, Hashable, Codable, Sendable {

    /// 정기 복용인지 필요시(PRN)인지.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case scheduled
        case asNeeded

        public var labelKo: String {
            switch self {
            case .scheduled: return "정기"
            case .asNeeded: return "필요시"
            }
        }

        public var labelEn: String {
            switch self {
            case .scheduled: return "Scheduled"
            case .asNeeded: return "As needed"
            }
        }

        public func label(_ language: JanjanLanguage) -> String {
            language == .english ? labelEn : labelKo
        }
    }

    /// 복용 중인지 중단했는지.
    public enum Status: String, Codable, Sendable, CaseIterable {
        case active
        case stopped

        public var labelKo: String {
            switch self {
            case .active: return "복용 중"
            case .stopped: return "중단"
            }
        }

        public var labelEn: String {
            switch self {
            case .active: return "Taking"
            case .stopped: return "Stopped"
            }
        }

        public func label(_ language: JanjanLanguage) -> String {
            language == .english ? labelEn : labelKo
        }
    }

    /// 제형. 목록에 없는 형태는 `other` 로 두고 이름에 적는다.
    public enum Form: String, Codable, Sendable, CaseIterable {
        case tablet
        case capsule
        case extendedRelease
        case orallyDisintegrating
        case liquid
        case patch
        case injection
        case other

        public var labelKo: String {
            switch self {
            case .tablet: return "정제"
            case .capsule: return "캡슐"
            case .extendedRelease: return "서방정"
            case .orallyDisintegrating: return "구강붕해정"
            case .liquid: return "시럽·액상"
            case .patch: return "패치"
            case .injection: return "주사"
            case .other: return "기타"
            }
        }

        public var labelEn: String {
            switch self {
            case .tablet: return "Tablet"
            case .capsule: return "Capsule"
            case .extendedRelease: return "Extended-release"
            case .orallyDisintegrating: return "Dissolving tablet"
            case .liquid: return "Liquid"
            case .patch: return "Patch"
            case .injection: return "Injection"
            case .other: return "Other"
            }
        }

        public func label(_ language: JanjanLanguage) -> String {
            language == .english ? labelEn : labelKo
        }

        /// 반 알로 쪼갤 수 있는 제형인지. 캡슐·서방정·패치는 쪼개지 않는다.
        public var isSplittable: Bool {
            switch self {
            case .tablet, .orallyDisintegrating, .other: return true
            case .capsule, .extendedRelease, .liquid, .patch, .injection: return false
            }
        }
    }

    public var id: UUID
    /// 사용자가 보는 이름. 상품명·성분명 무엇이든 자유 입력.
    public var name: String
    /// "25mg", "0.5mg" 처럼 화면에 그대로 붙는 용량 문자열.
    public var strengthText: String
    public var form: Form
    public var kind: Kind
    public var status: Status
    public var note: String
    /// 번들 약 카탈로그(`drug_catalog.json`)의 항목 ID. 없으면 자유 입력 약.
    public var catalogID: String?
    /// "잠들기 쉽게" 같은 한 줄 용도 메모. 진단명이 아니라 사용자 자신의 말.
    public var purposeLine: String
    /// 가장 최근 중단 구간이 시작한 시각. 다시 복용으로 바꿔도 지우지 않는다 -
    /// `resumedAt` 과 짝을 이뤄 "그동안 쉬었다" 는 사실을 남긴다.
    ///
    /// "기록 없이 지나간 시간대" 가 이걸 본다 - 중단하기 **전**의 빈 시간대는
    /// 여전히 사실이므로 계속 들되, 중단한 뒤의 침묵은 빠트림이 아니다.
    /// 이 약을 등록한 시각.
    ///
    /// **계획을 과거로 소급하지 않기 위해 필요하다.** DayPlan 은 지난 날의
    /// 계획을 저장하지 않고 매번 지금의 스케줄로 다시 만든다. 등록 시각이
    /// 없으면 오늘 넣은 약이 지난 한 달 내내 있었던 것이 되고, 오늘 화면은
    /// 등록하자마자 "기록 없이 지나간 시간대 6번" 을 띄운다. 그 자리에서
    /// "기억나지 않아요" 를 누르면 존재한 적 없는 처방의 미기록 사건이
    /// 저장되고, 그것이 진료 리포트의 복약률에 섞인다(QA 2026-09-19).
    ///
    /// 저장소에는 처음부터 있던 값인데 core 모델로 넘어오지 않고 버려지고
    /// 있었다 - 이어 주기만 하면 된다.
    ///
    /// **옵셔널인 이유**: 저장소를 거치지 않고 손으로 만든 값(테스트·예시)은
    /// 언제부터였는지 모른다. 모르는 것을 "지금부터" 로 단정하면 그 값으로
    /// 만든 과거 계획이 통째로 비어 버린다. 모르면 막지 않는다.
    public var createdAt: Date?

    public var stoppedAt: Date?
    /// 가장 최근 중단 구간이 끝난(다시 복용을 시작한) 시각.
    /// `[stoppedAt, resumedAt)` 사이의 빈 시간대는 빠트림이 아니다.
    /// 여러 번 중단·재개하면 마지막 구간만 남는다 - 그 전 구간까지 완벽히
    /// 되짚는 것은 이 도구의 몫(어제오늘 빠트렸나)을 넘는다.
    public var resumedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        strengthText: String = "",
        form: Form = .tablet,
        kind: Kind = .scheduled,
        status: Status = .active,
        note: String = "",
        catalogID: String? = nil,
        purposeLine: String = "",
        stoppedAt: Date? = nil,
        resumedAt: Date? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.strengthText = strengthText
        self.form = form
        self.kind = kind
        self.status = status
        self.note = note
        self.catalogID = catalogID
        self.purposeLine = purposeLine
        self.stoppedAt = stoppedAt
        self.resumedAt = resumedAt
        self.createdAt = createdAt
    }

    /// "쿠에티아핀 25mg" 처럼 한 줄로 합친 표시용 문자열.
    public var displayTitle: String {
        strengthText.isEmpty ? name : "\(name) \(strengthText)"
    }
}
