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

    /// 앱과 위젯이 같은 파일을 보게 하는 그룹을 실제로 열 수 있는가.
    ///
    /// **반드시 먼저 물어야 한다.** entitlement 없는 그룹을 SwiftData 에 넘기면
    /// 오류를 던지는 대신 `fatalError` 로 프로세스를 끝낸다 — `try?` 로 못 잡는다.
    /// 처음에는 단계별 후퇴가 이걸 받아 줄 것이라 여겼는데, 그 코드에 닿기 전에
    /// 앱이 죽었다. 서명 없는 CI 빌드가 실행 즉시 종료됐다.
    ///
    /// FileManager 는 같은 질문에 nil 로 답한다. 그래서 여기로 묻는다.
    private static var isAppGroupReachable: Bool {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Janjan.appGroupID) != nil
    }

    /// 그룹을 쓸 수 있는지 / iCloud 를 붙일지에 따른 네 가지 조합.
    ///
    /// 삼항 연산자로 겹쳐 쓰지 않는다. 어느 조합이 무엇인지 눈으로 보이는 편이,
    /// 나중에 한 갈래만 고칠 때 안전하다.
    private static func configuration(
        schema: Schema,
        useGroup: Bool,
        cloudKit: Bool
    ) -> ModelConfiguration {
        switch (useGroup, cloudKit) {
        case (true, true):
            return ModelConfiguration(
                "Janjan",
                schema: schema,
                groupContainer: .identifier(Janjan.appGroupID),
                cloudKitDatabase: .private(Janjan.cloudKitContainerID)
            )
        case (true, false):
            return ModelConfiguration(
                "Janjan",
                schema: schema,
                groupContainer: .identifier(Janjan.appGroupID)
            )
        case (false, true):
            return ModelConfiguration(
                "Janjan",
                schema: schema,
                cloudKitDatabase: .private(Janjan.cloudKitContainerID)
            )
        case (false, false):
            return ModelConfiguration("Janjan", schema: schema)
        }
    }

    static func make() -> ModelContainer {
        let schema = Schema(JanjanSchema.allModels)

        // 한 번만 묻고 그 답을 아래 전부에 쓴다.
        let useGroup = isAppGroupReachable
        if !useGroup {
            // 앱은 멀쩡히 돌아간다. 위젯만 앱 데이터를 못 보고 비어 보인다.
            logger.warning("App Group 을 열 수 없습니다. 앱 전용 저장소를 씁니다(위젯은 비어 보입니다).")
        }

        if !isCloudKitDisabledByEnvironment {
            let cloudConfiguration = configuration(schema: schema, useGroup: useGroup, cloudKit: true)
            if let container = try? ModelContainer(for: schema, configurations: cloudConfiguration) {
                activeStorage = .cloudKit
                return container
            }
            logger.warning("CloudKit 컨테이너를 열지 못했습니다. 로컬 저장소로 물러납니다.")
        }

        let localConfiguration = configuration(schema: schema, useGroup: useGroup, cloudKit: false)
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
