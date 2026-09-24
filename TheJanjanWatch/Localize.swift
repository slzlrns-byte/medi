import Foundation
import JanjanCore

/// 워치의 언어. 워치에는 설정이 없다 — 폰이 스냅샷에 실어 보낸 것을 따른다.
/// 스냅샷이 오기 전(placeholder)에는 기본 언어로 그린다.
func t(_ ko: String, _ en: String) -> String {
    WatchSessionManager.shared.snapshot.language == .english ? en : ko
}
