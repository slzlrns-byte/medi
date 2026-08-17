import Foundation
import OSLog
import SwiftData
import JanjanCore

/// ModelContainer 를 만드는 곳. 실패해도 앱이 죽지 않는 것이 유일한 목표다.
///
/// 세 단계로 물러난다:
///   1. iCloud(CloudKit private DB) 와 함께
///   2. 로컬 파일 저장소만 — iCloud 미로그인, entitlement 미부여, 시뮬레이터
///   3. 메모리 저장소 — 파일조차 만들 수 없는 CI 러너 같은 환경
///
/// 3단계까지 갔다면 이번 실행의 기록은 남지 않는다는 뜻이라 `activeStorage` 로 알려 준다.
enum JanjanModelContainer {

    private static let logger = Logger(subsystem: Janjan.appBundleID, category: "persistence")

    enum Storage: String {
        case cloudKit
        case localFile
        case inMemory

        var labelKo: String {
            switch self {
            case .cloudKit: return "iCloud 동기화 사용 중"
            case .localFile: return "이 기기에만 저장 중"
            case .inMemory: return "임시 저장 (앱을 닫으면 사라집니다)"
            }
        }
    }

    /// 어떤 저장소로 열렸는지. 설정 화면에서 그대로 보여 준다.
    private(set) static var activeStorage: Storage = .cloudKit

    /// iCloud 동기화를 끄고 싶을 때(테스트 러너, 추후 설정 토글) 쓰는 스위치.
    static var isCloudKitDisabledByEnvironment: Bool {
        ProcessInfo.processInfo.environment["JANJAN_DISABLE_CLOUDKIT"] == "1"
    }

    static func make() -> ModelContainer {
        let schema = Schema(JanjanSchema.allModels)

        if !isCloudKitDisabledByEnvironment {
            let cloudConfiguration = ModelConfiguration(
                "Janjan",
                schema: schema,
                cloudKitDatabase: .private(Janjan.cloudKitContainerID)
            )
            if let container = try? ModelContainer(for: schema, configurations: cloudConfiguration) {
                activeStorage = .cloudKit
                return container
            }
            logger.warning("CloudKit 컨테이너를 열지 못했습니다. 로컬 저장소로 물러납니다.")
        }

        let localConfiguration = ModelConfiguration("Janjan", schema: schema)
        if let container = try? ModelContainer(for: schema, configurations: localConfiguration) {
            activeStorage = .localFile
            return container
        }
        logger.error("로컬 저장소도 열지 못했습니다. 메모리 저장소로 물러납니다.")

        let memoryConfiguration = ModelConfiguration(
            "Janjan",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        if let container = try? ModelContainer(for: schema, configurations: memoryConfiguration) {
            activeStorage = .inMemory
            return container
        }

        // 여기까지 왔다면 스키마 정의 자체가 잘못된 것이다(CloudKit 제약 위반 등).
        // 조용히 넘어가면 원인을 영영 못 찾으므로 메시지를 남기고 멈춘다.
        fatalError("SwiftData 스키마를 초기화할 수 없습니다. Records.swift 의 CloudKit 제약을 확인하세요.")
    }
}
