import XCTest
@testable import JanjanCore

/// 직접 넣은 시간대(하루 다섯 번째부터)의 규칙.
final class CustomSlotTests: XCTestCase {

    func testCustomSlotKnowsItself() {
        XCTAssertTrue(DoseSlot.custom(TimeOfDay(hour: 14, minute: 30)).isCustom)
        XCTAssertFalse(DoseSlot.morning.isCustom)
    }

    /// 저장 키가 시각을 그대로 실어 되돌아와야 어제 등록한 14:30 이 내일도 14:30 이다.
    func testCustomSlotStorageRoundTrip() {
        let slot = DoseSlot.custom(TimeOfDay(hour: 14, minute: 30))
        XCTAssertEqual(DoseSlot(storageKey: slot.storageKey), slot)
    }

    /// 직접 넣은 시간대의 이름은 시각 그 자체다. 화면들은 이 사실을 전제로
    /// 라벨과 시각을 겹쳐 말하지 않는다.
    func testCustomSlotLabelIsItsTime() {
        let slot = DoseSlot.custom(TimeOfDay(hour: 14, minute: 30))
        XCTAssertEqual(slot.labelKo, "14:30")
    }
}
