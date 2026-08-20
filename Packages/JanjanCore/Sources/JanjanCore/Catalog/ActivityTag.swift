import Foundation

/// 그날 무엇을 했는지 붙이는 태그 (설계 09절).
///
/// 카탈로그 파일로 빼지 않고 코드에 둔다. 열두 개뿐이고 사용자가 늘릴 것도 아니라
/// JSON 한 장을 더 얹을 값이 없다.
///
/// **좋고 나쁨을 나누지 않는다.** 술도 운동도 같은 회색 칩이고 순서도 평가가 아니다.
/// 무엇이 기분과 겹쳤는지는 진료실에서 사람이 읽는다.
public struct ActivityTag: Identifiable, Hashable, Sendable {

    public let id: String
    public let nameKo: String

    public init(id: String, nameKo: String) {
        self.id = id
        self.nameKo = nameKo
    }

    public static let presets: [ActivityTag] = [
        ActivityTag(id: "outdoors", nameKo: "외출"),
        ActivityTag(id: "exercise", nameKo: "운동"),
        ActivityTag(id: "people", nameKo: "사람 만남"),
        ActivityTag(id: "work", nameKo: "일·학업"),
        ActivityTag(id: "chores", nameKo: "집안일"),
        ActivityTag(id: "sunlight", nameKo: "햇빛"),
        ActivityTag(id: "nap", nameKo: "낮잠"),
        ActivityTag(id: "alcohol", nameKo: "술"),
        ActivityTag(id: "caffeine", nameKo: "카페인"),
        ActivityTag(id: "smoking", nameKo: "담배"),
        ActivityTag(id: "period", nameKo: "생리"),
        ActivityTag(id: "unwell", nameKo: "몸이 아픔")
    ]

    /// 저장된 id 를 화면에 보일 이름으로. 목록에 없는 id 는 그대로 보여 준다 —
    /// 나중에 태그를 지우더라도 옛 기록의 글자가 사라지지는 않게.
    public static func nameKo(forID id: String) -> String {
        presets.first { $0.id == id }?.nameKo ?? id
    }
}
