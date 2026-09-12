import Foundation
import JanjanCore

// 앱 전체가 저장소에서 나온 `Medication` 을 화면에 내보내기 직전에 거치는 한 곳.
// 이 파일은 앱과 위젯 두 타깃에 들어간다.

extension Medication {
    /// 화면에 내보내기 직전의 사본. 성분명 표기가 고른 언어를 따른다.
    /// 저장소로 돌아가지 않는다 - 표시 전용이다.
    var displayReady: Medication {
        var copy = self
        copy.name = DrugNames.display(name, in: JanjanLanguage.current)
        return copy
    }
}
