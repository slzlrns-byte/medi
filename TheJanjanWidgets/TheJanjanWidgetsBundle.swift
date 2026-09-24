import SwiftUI
import WidgetKit

/// 위젯 묶음.
///
/// 홈 화면 것과 잠금화면 것을 따로 둔다. 홈 화면에는 누르는 버튼이 있고
/// 잠금화면에는 없다 — 이유는 NextDoseLockScreenWidget 주석에 적어 뒀다.
@main
struct TheJanjanWidgetsBundle: WidgetBundle {

    var body: some Widget {
        NextDoseWidget()
        NextDoseLockScreenWidget()
    }
}
