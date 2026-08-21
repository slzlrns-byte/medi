import CryptoKit
import Foundation
import OSLog
import Security
import JanjanCore

/// 네 자리 잠금 번호를 보관하는 곳.
///
/// **번호 자체는 저장하지 않는다.** 무작위 소금을 붙여 여러 번 해싱한 값만 남긴다.
/// 네 자리는 만 가지뿐이라 해시가 번호를 지켜 주지는 못한다 — 지켜 주는 것은 키체인이고,
/// 해시는 그 뒤의 한 겹이다. 사람들은 폰·현관·은행에 같은 네 자리를 쓰므로,
/// 혹시 키체인이 통째로 새더라도 그 번호가 평문으로 굴러다니지는 않게 한다.
///
/// **저장된 항목이 곧 "잠금이 켜져 있다" 는 뜻이다.** 켜짐 여부를 UserDefaults 에 따로
/// 두면 둘이 어긋나는 날이 오고, 그날 사용자는 열 수 없는 잠금 앞에 선다.
enum PasscodeStore {

    private static let logger = Logger(subsystem: Janjan.appBundleID, category: "passcode")

    private static let service = Janjan.appBundleID + ".applock"
    private static let account = "passcode"

    /// 해싱을 되풀이하는 횟수. 만 가지를 전부 훑는 데 드는 시간을 늘린다.
    private static let iterations = 120_000

    private struct Stored: Codable {
        let version: Int
        let salt: Data
        let hash: Data
    }

    // MARK: - 읽기

    /// 잠금이 켜져 있는가.
    static var isSet: Bool { load() != nil }

    /// 맞는 번호인가. 저장된 것이 없으면 항상 false — 잠금이 없으니 물어볼 일도 없다.
    static func verify(_ pin: String) -> Bool {
        guard let stored = load() else { return false }
        let candidate = digest(pin: pin, salt: stored.salt)
        // 길이가 같은 두 해시를 상수 시간으로 견준다.
        return candidate.withUnsafeBytes { lhs in
            stored.hash.withUnsafeBytes { rhs in
                lhs.count == rhs.count && timingsafe(lhs, rhs)
            }
        }
    }

    // MARK: - 쓰기

    /// 번호를 새로 정하거나 바꾼다. 소금은 매번 새로 뽑는다.
    @discardableResult
    static func save(_ pin: String) -> Bool {
        guard Passcode.validate(pin) == .ok else { return false }

        var salt = Data(count: 32)
        let filled = salt.withUnsafeMutableBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, base)
        }
        guard filled == errSecSuccess else {
            logger.error("소금을 만들지 못했습니다.")
            return false
        }

        let stored = Stored(version: 1, salt: salt, hash: digest(pin: pin, salt: salt))
        guard let data = try? JSONEncoder().encode(stored) else { return false }

        remove()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // 기기가 잠금 해제된 동안에만 읽히고, **이 기기 밖으로 나가지 않는다.**
            // iCloud 키체인으로 새 폰에 따라가지 않는다는 뜻이라, 기기를 바꾸면
            // 잠금이 꺼진 채로 시작한다. 일부러 그렇게 뒀다 — 이 앱에는 잠긴 것을
            // 풀어 줄 서버가 없어서, 따라가는 쪽이 잠겨 나갈 위험을 만든다.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("잠금 번호를 저장하지 못했습니다: \(status, privacy: .public)")
            return false
        }
        return true
    }

    /// 잠금을 끈다. 저장된 것이 없어도 조용히 넘어간다.
    static func remove() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("잠금 번호를 지우지 못했습니다: \(status, privacy: .public)")
        }
    }

    // MARK: - 안쪽

    private static func load() -> Stored? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }

    private static func digest(pin: String, salt: Data) -> Data {
        var value = Data(salt)
        value.append(Data(pin.utf8))

        for _ in 0..<iterations {
            var round = Data(SHA256.hash(data: value))
            // 소금을 매 회 다시 섞어 준비 계산(레인보우 테이블)을 막는다.
            round.append(salt)
            value = round
        }
        return Data(SHA256.hash(data: value))
    }

    /// 앞자리가 다르다고 일찍 돌아가지 않는다. 걸리는 시간으로 번호를 좁히지 못하게.
    private static func timingsafe(
        _ lhs: UnsafeRawBufferPointer,
        _ rhs: UnsafeRawBufferPointer
    ) -> Bool {
        var difference: UInt8 = 0
        for index in 0..<lhs.count {
            difference |= lhs[index] ^ rhs[index]
        }
        return difference == 0
    }
}
