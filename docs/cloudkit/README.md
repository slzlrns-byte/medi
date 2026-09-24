# CloudKit 스키마 (iCloud.com.thejanjan.app)

`janjan-schema.ckdb` 는 `TheJanjan/Persistence/Records.swift` 의 SwiftData 모델
9개를 CloudKit 스키마 언어로 옮긴 것이다. Mac 없이 CloudKit 대시보드의
**Import Schema...** 로 개발 환경에 넣고 **Deploy Schema Changes...** 로
프로덕션에 올리기 위해 손으로 썼다(2026-09-23).

## 왜 손으로 썼나

TestFlight·스토어 빌드는 프로덕션 환경을 쓰고, 프로덕션 스키마는 개발
환경에서 배포해야만 생긴다. 개발 환경 스키마는 Xcode 로 직접 실행한
빌드가 만드는데, 이 프로젝트는 모든 빌드가 CI 에서 나와 개발 환경이
비어 있었다. 1.0 제출 뒤에 발견(양쪽 다 `Users` 뿐).

## 타입 대응 (애플 문서 "Reading CloudKit Records for Core Data")

| Swift | Core Data | CloudKit |
|---|---|---|
| `Int`, `Int?`, `Bool?` | Integer 64 / Boolean | `INT64` |
| `Decimal` | Decimal (NSDecimalNumber → NSNumber) | `DOUBLE` |
| `UUID`, `UUID?` | UUID | `STRING` |
| `Date`, `Date?` | Date | `TIMESTAMP` |
| `String`, `String?` | String | `STRING` + `<이름>_ckAsset ASSET` |
| `[Int]`, `[String]` | Transformable | `BYTES` + `<이름>_ckAsset ASSET` |

- 레코드 타입은 `CD_<클래스 이름>`, 필드는 `CD_<속성 이름>`, 모든 타입에 `CD_entityName STRING`.
- 관계는 쓰지 않으므로 `CDMR` 타입이 없다.
- 길이가 변하는 타입(String·Transformable)은 1MB 를 넘으면 자산으로 바뀌므로 `_ckAsset` 칸을 함께 둔다.

## 모델을 바꿀 때

프로덕션에 올라간 레코드 타입과 필드는 **지우거나 이름을 바꿀 수 없다**.
더할 수만 있다. 속성을 더하면 이 파일에도 같은 규칙으로 줄을 더해
개발 환경에 다시 Import 하고 배포한다. 속성을 빼면 파일에서는 그대로 두고
앱만 안 쓰면 된다.

## 검증

배포 뒤 TestFlight 앱(프로덕션)에서 약 하나를 등록하고, 대시보드에서
**Act As iCloud Account...** 로 본인 계정에 들어가 Production →
Records → Private Database → `com.apple.coredata.cloudkit.zone` 에서
`CD_MedicationRecord` 와 `CD_ScheduleRecord` 를 조회한다. 둘 다 나오면
STRING·TIMESTAMP·DOUBLE·BYTES 가 전부 맞은 것이다.

2026-09-23 검증 완료: 배포 뒤 TestFlight 빌드 23 의 RecordSave 가 프로덕션에서
SUCCESS(6건 삽입, CD_StockEventRecord 포함). 대시보드에서 기록이 안 보이면
"Act As iCloud Account" 의 계정이 아이폰의 Apple ID 와 같은지 먼저 본다 - 로그의
`userId` 와 대행 계정 ID 가 다르면 다른 계정이다.
