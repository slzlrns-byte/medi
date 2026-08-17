# 더잔잔 (The Janjan)

**더 잔잔한 하루를 위해** — 정신과 투약·기분·증상 기록 iOS/watchOS 앱

**상태 · 코드 골격 v0.1.0 (설계 초안 v0.6 기준)** — 화면과 로직의 뼈대가 올라갔습니다.
재고 계산은 완성되어 단위 테스트로 잠겨 있고, 화면은 아직 예시 데이터로 그려집니다.

## 스택

- SwiftUI · iOS 17+ / watchOS 10+ (네이티브, iOS 전용)
- SwiftData + CloudKit **private** DB (개발자 서버 없음)
- StoreKit 2 구독 (월 ₩2,900 / 연 ₩19,900, 7일 체험은 연간만) — 아직 미구현
- 로그인 없음 · 서버 없음 · 광고 없음 · 분석 SDK 없음
- 서체 SUIT Light(제목) + Pretendard(본문), 둘 다 SIL OFL 1.1

## 문서

- [설계 맵 v0.6](docs/design-map.html) — 원칙 / 디자인 시스템 / 화면 맵 / 흐름 / 재고 로직 / Pro 범위 / 심사 체크리스트
- [결정 로그](docs/decisions.md)
- [**애플 · 깃허브 설정 (한 번만)**](docs/apple-setup.md) — 개발자 계정부터 TestFlight 설치까지 클릭 순서
- [화면 초안 이미지](docs/shots/)
- [데이터 카탈로그 설명](data/README.md)
- 정책 페이지 원본: [docs/site/](docs/site/) (GitHub Pages: 저장소 Settings → Pages → Deploy from branch → main /docs 로 켜면 https://slzlrns-byte.github.io/medi/site/privacy.html 로 열림)

## 폴더

```
project.yml            XcodeGen 스펙 — 여기서 TheJanjan.xcodeproj 를 만든다
Packages/JanjanCore/   순수 로직 (Foundation 만). 재고·복약률·카탈로그·디자인 토큰 + 테스트
TheJanjan/             iOS 앱 (SwiftUI, SwiftData, 알림, 번들 서체)
TheJanjanWatch/        watchOS 앱 (SwiftUI, WatchConnectivity)
TheJanjanTests/        iOS 단위 테스트 (앱 계층 얇게)
fastlane/              Appfile / Matchfile / Fastfile
.github/workflows/     ci.yml · testflight.yml
docs/                  설계 맵(HTML), 결정 로그, 설정 가이드, 화면 초안 PNG
design/                디자인 토큰(tokens.json), 웹용 가변 서체
data/                  앱에 번들할 JSON 카탈로그 + JSON Schema (원본)
```

`TheJanjan.xcodeproj` 는 **커밋하지 않습니다.** `project.yml` 하나가 진실이고,
프로젝트 파일은 매번 새로 생성합니다.

## 빌드·배포 (GitHub Actions만 사용)

개발 머신에 맥과 Xcode가 없습니다. **컴파일러는 CI입니다.**
빌드·테스트·서명·업로드가 전부 GitHub의 macOS 러너에서 일어납니다.

| 워크플로 | 언제 | 무엇을 | 시크릿 |
| --- | --- | --- | --- |
| [`ci.yml`](.github/workflows/ci.yml) | main 에 push · PR · 수동 | xcodegen → entitlements 검사 → 서체 무결성 검사 → `swift test` → 시뮬레이터 빌드·테스트 | 없음 |
| [`testflight.yml`](.github/workflows/testflight.yml) | 수동 실행 · `v*` 태그 | match 서명 → 아카이브 → TestFlight 업로드 | 7개 (아래) |

필요한 저장소 시크릿 7개 — **값을 어디서 얻는지는 [docs/apple-setup.md](docs/apple-setup.md) 에 클릭 순서로 적어 두었습니다.**

`APPLE_TEAM_ID` · `ASC_ISSUER_ID` · `ASC_KEY_ID` · `ASC_KEY_CONTENT` ·
`MATCH_GIT_URL` · `MATCH_GIT_BASIC_AUTHORIZATION` · `MATCH_PASSWORD`

TestFlight **첫 실행에서만** `first_run` 입력을 켭니다(인증서를 새로 발급해
비공개 저장소 `medi-certs` 에 넣습니다). 두 번째부터는 반드시 끕니다.

### 맥이 생겼다면 (선택)

```sh
brew install xcodegen
xcodegen generate
open TheJanjan.xcodeproj
```

순수 로직만 확인하려면 Xcode 없이도 됩니다:

```sh
swift test --package-path Packages/JanjanCore
```

## 코드 지도

- **`Packages/JanjanCore/Sources/JanjanCore/Inventory/InventoryCalculator.swift`**
  재고는 저장하지 않고 사건의 합으로 매번 다시 계산합니다.
  마지막 직접 정정이 기준점 → 이후 보충 더하기 → **복용함만** 빼기.
  건너뜀·미기록은 차감하지 않고, 대신 소진 예측에 최근 4주 복약률을 곱해 보정합니다.
  개수는 전부 `Decimal` (반 알 0.5, 최소 단위 0.25).
- **`Design/Tokens.swift`** — `design/tokens.json` 의 Swift 사본. SwiftUI를 import하지 않아 테스트 가능합니다.
- **`TheJanjan/Persistence/Records.swift`** — SwiftData 모델. CloudKit 제약(모든 속성 기본값,
  unique 금지, 관계 금지)을 지키려고 관계 대신 UUID 외래키만 씁니다.
- **`TheJanjan/Notifications/NotificationManager.swift`** — `DOSE_REMINDER` 카테고리와
  복용함/건너뜀/30분 뒤 액션. 앱을 열지 않고 백그라운드에서 기록합니다.
- **`TheJanjan/Security/AppLockManager.swift`** — 앱 잠금(Face ID · Touch ID · 기기 암호).
  앱 전용 비밀번호를 만들지 않고 `deviceOwnerAuthentication` 하나만 씁니다.
  켤 때 먼저 인증해서 "열 수 없는 기기에서 잠겨 나가는" 경로를 막고,
  다시 잠글 시점 판단은 `JanjanCore/Security/LockPolicy.swift` 의 순수 함수가 합니다.

## 면책

이 앱과 문서는 의료 조언이 아니며, 복용 변경은 담당 의사와 상의해야 합니다.
위기 상담: **109**(자살예방상담전화, 24시간) · **1577-0199**(정신건강위기상담) · 응급 112 / 119.

© 2026 slzlrns. All rights reserved.
