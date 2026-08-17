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

    public init(
        id: UUID = UUID(),
        name: String,
        strengthText: String = "",
        form: Form = .tablet,
        kind: Kind = .scheduled,
        status: Status = .active,
        note: String = "",
        catalogID: String? = nil,
        purposeLine: String = ""
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
    }

    /// "쿠에티아핀 25mg" 처럼 한 줄로 합친 표시용 문자열.
    public var displayTitle: String {
        strengthText.isEmpty ? name : "\(name) \(strengthText)"
    }
}
