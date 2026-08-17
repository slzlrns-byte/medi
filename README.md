# 더잔잔 (The Janjan)

**더 잔잔한 하루를 위해** — 정신과 투약·기분·증상 기록 iOS/watchOS 앱

**상태 · 설계 초안 v0.6 (2026-08-17)** — 아직 코드 골격은 없고, 설계 문서와 디자인 토큰·데이터 카탈로그만 있습니다.

## 스택

- SwiftUI · iOS 17+ / watchOS 10+ (네이티브, iOS 전용)
- SwiftData + CloudKit **private** DB (개발자 서버 없음)
- StoreKit 2 구독 (월 ₩2,900 / 연 ₩19,900, 7일 체험은 연간만)
- 로그인 없음 · 서버 없음 · 광고 없음 · 분석 SDK 없음
- 서체 SUIT Variable(제목) + Pretendard Variable(본문), 둘 다 SIL OFL 1.1

## 문서

- [설계 맵 v0.6](docs/design-map.html) — 원칙 / 디자인 시스템 / 화면 맵 / 흐름 / 재고 로직 / Pro 범위 / 심사 체크리스트
- [결정 로그](docs/decisions.md)
- [화면 초안 이미지](docs/shots/)
- [데이터 카탈로그 설명](data/README.md)

## 폴더

```
docs/          설계 맵(HTML), 결정 로그, 화면 초안 PNG
design/        디자인 토큰(tokens.json), 번들 서체
data/          앱에 번들할 JSON 카탈로그 + JSON Schema
.github/       CI 워크플로 골격 (아직 비활성)
```

## 맥에서 시작하기

> 아직 Xcode 프로젝트가 없습니다. XcodeGen으로 `project.yml` 하나에서 iOS·watchOS 타깃을 생성할 예정입니다.

```sh
git clone https://github.com/slzlrns-byte/medi.git
cd medi
# brew install xcodegen
# xcodegen generate
# open TheJanjan.xcodeproj
```

프로젝트 골격이 올라오면 이 절과 `.github/workflows/ios-testflight.yml`을 함께 활성화합니다.

## 면책

이 앱과 문서는 의료 조언이 아니며, 복용 변경은 담당 의사와 상의해야 합니다.
위기 상담: **109**(자살예방상담전화, 24시간) · **1577-0199**(정신건강위기상담) · 응급 112 / 119.

© 2026 slzlrns. All rights reserved.
