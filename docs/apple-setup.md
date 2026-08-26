# 애플 · 깃허브 설정 (한 번만 하면 됩니다)

**맥이 없어도 됩니다.** 빌드·서명·업로드는 전부 GitHub 서버(맥 러너)에서 일어납니다.
여기 적힌 건 전부 **웹 브라우저에서 클릭하는 일**이고, 딱 한 군데(파일을 base64로 바꾸는 것)에서만
윈도우 PowerShell 명령을 씁니다.

순서대로 하세요. a → h 를 다 끝내면 아이폰 TestFlight 에 앱이 설치됩니다.
처음 하면 **1~2시간** 걸립니다(애플 심사 대기 시간 제외).

> 미리 준비할 것: 애플 ID, 신용카드(개발자 프로그램 연회비 US$99),
> 깃허브 계정(`slzlrns-byte`), 그리고 값을 적어 둘 메모장 하나.

---

## a. Apple Developer Program 가입 · Team ID 찾기

1. https://developer.apple.com/programs/enroll/ 로 갑니다.
2. 애플 ID로 로그인합니다. **2단계 인증이 켜져 있어야** 진행됩니다.
3. **개인(Individual)** 으로 가입합니다. 법인(Organization)은 D-U-N-S 번호가 필요해 훨씬 오래 걸립니다.
   개인으로 가입하면 App Store 판매자 이름이 **본인 실명**으로 나옵니다. 상호명을 쓰고 싶다면
   나중에 법인으로 전환해야 하니 지금 결정하세요.
4. 연회비 US$99를 결제합니다. 승인까지 보통 몇 시간, 길면 이틀 걸립니다.
5. 승인 메일을 받으면 https://developer.apple.com/account 로 들어갑니다.
6. 왼쪽 메뉴 **Membership details**(또는 Membership)를 누릅니다.
7. **Team ID** 라고 적힌 10자리 영숫자(예: `A1B2C3D4E5`)를 메모합니다.
   → 이게 나중에 시크릿 `APPLE_TEAM_ID` 입니다.

---

## b. App Store Connect API 키 만들기

CI가 애플과 대화할 때 쓰는 열쇠입니다. 애플 ID/비밀번호를 깃허브에 넣지 않기 위한 방법입니다.

1. https://appstoreconnect.apple.com 에 로그인합니다.
2. 위쪽 **사용자 및 액세스**(Users and Access)를 누릅니다.
3. 탭 중에서 **통합**(Integrations) → 왼쪽 **App Store Connect API** 를 누릅니다.
4. **팀 키**(Team Keys) 탭인지 확인합니다. (개별 키가 아니라 팀 키입니다.)
5. **+** 버튼을 누릅니다.
6. 이름은 `GitHub Actions`, 액세스 권한은 **App Manager** 를 고르고 생성합니다.
   - Developer 권한은 TestFlight 업로드가 막힐 수 있습니다. Admin 은 과합니다.
7. 목록에 새 줄이 생깁니다. 여기서 세 가지를 챙깁니다.
   - **Issuer ID** — 목록 위쪽에 한 줄로 떠 있는 긴 문자열 → 시크릿 `ASC_ISSUER_ID`
   - **키 ID** — 새로 만든 줄의 KEY ID 열 (10자리) → 시크릿 `ASC_KEY_ID`
   - **API 키 다운로드** 링크 → `AuthKey_XXXXXXXXXX.p8` 파일
8. > **⚠ .p8 파일은 딱 한 번만 받을 수 있습니다.**
   > 다시 받을 수 없고, 잃어버리면 키를 폐기하고 처음부터 다시 만들어야 합니다.
   > 다운로드 폴더에 두지 말고 **비밀번호 관리자나 개인 클라우드에 즉시 백업**하세요.
   > (이전 앱에서 이걸 놓쳐 키를 두 번 만든 적이 있습니다.)

---

## c. App ID 2개와 iCloud 컨테이너 만들기

아이폰 앱과 워치 앱은 서로 다른 번들 ID를 씁니다. 둘 다 미리 등록해야 서명이 통과합니다.

### c-1. iCloud 컨테이너 먼저

1. https://developer.apple.com/account/resources/identifiers/list 로 갑니다.
2. 왼쪽 위 드롭다운(기본값 `App IDs`)을 **iCloud Containers** 로 바꿉니다.
3. **+** → Description 은 `TheJanjan`, Identifier 는 정확히
   **`iCloud.com.thejanjan.app`** → Continue → Register.

### c-2. 아이폰 앱 ID

1. 다시 드롭다운을 **App IDs** 로 바꾸고 **+** 를 누릅니다.
2. **App** 을 고르고 Continue.
3. Description `The Janjan`, Bundle ID 는 **Explicit** 을 고르고 **`com.thejanjan.app`**.
4. **Capabilities** 목록에서 아래 두 개를 체크합니다.
   - **iCloud** → 체크하면 아래에 `Configure` 버튼이 생깁니다.
     누르고 **CloudKit** 을 고른 뒤 위에서 만든 `iCloud.com.thejanjan.app` 을 체크 → Save.
   - **Push Notifications** → 체크만 합니다.
5. Continue → Register.

### c-3. 워치 앱 ID

1. **+** → **App** → Continue.
2. Description `The Janjan Watch`, Bundle ID **Explicit** → **`com.thejanjan.app.watchkitapp`**.
   (반드시 아이폰 번들 ID 뒤에 `.watchkitapp` 을 붙인 형태여야 합니다.)
3. Capabilities 에서 **iCloud** 를 체크하고 Configure → **CloudKit** →
   같은 컨테이너 `iCloud.com.thejanjan.app` 체크 → Save.
   - 워치 앱도 같은 컨테이너를 entitlements 에 선언해 두었기 때문에 여기서 빠지면 서명이 실패합니다.
4. Push Notifications 는 워치엔 필요 없습니다. 체크하지 마세요.
5. Continue → Register.

---

## d. App Store Connect 에 앱 만들기

1. https://appstoreconnect.apple.com → **나의 앱**(My Apps) → **+** → **신규 앱**.
2. 입력값:

   | 칸 | 값 |
   | --- | --- |
   | 플랫폼 | **iOS** 만 체크 |
   | 이름 | `더잔잔` |
   | 기본 언어 | 한국어 |
   | 번들 ID | 목록에서 `com.thejanjan.app` 선택 |
   | SKU | `thejanjan` |
   | 사용자 액세스 | 전체 액세스 |

3. **생성**을 누릅니다. 이 단계까지만 하면 됩니다 — 스크린샷·설명은 나중에.
4. **유료 앱 계약**: 구독을 붙이기 전에 **비즈니스**(Agreements, Tax, and Banking)에서
   유료 앱 계약을 체결해야 합니다. TestFlight 테스트만 할 거면 지금은 건너뛰어도 됩니다.

---

## e. 인증서 저장소(medi-certs)와 PAT 만들기

인증서와 프로비저닝 프로파일을 **암호화해서 비공개 깃 저장소에 보관**합니다(fastlane match 방식).
이렇게 해야 맥 없이도 CI가 매번 같은 인증서로 서명할 수 있습니다.

1. https://github.com/new 로 갑니다.
2. Repository name **`medi-certs`**, **Private** 을 반드시 선택.
3. "Add a README file" 은 **체크하세요**(빈 저장소면 match 가 헷갈립니다).
4. Create repository.
5. 이제 PAT(개인 액세스 토큰)를 만듭니다.
   https://github.com/settings/tokens → **Tokens (classic)** → **Generate new token (classic)**.
6. Note 는 `janjan match`, Expiration 은 **No expiration**(또는 1년),
   Scopes 는 **`repo`** 하나만 체크 → Generate token.
7. `ghp_...` 로 시작하는 토큰이 **한 번만** 보입니다. 메모장에 복사해 두세요.

---

## f. GitHub Secrets 7개 등록

저장소 https://github.com/slzlrns-byte/medi → **Settings** → 왼쪽 **Secrets and variables** →
**Actions** → **New repository secret** 을 7번 반복합니다.

| 시크릿 이름 | 값 | 어디서 왔나 |
| --- | --- | --- |
| `APPLE_TEAM_ID` | 10자리 영숫자 | a-7 |
| `ASC_ISSUER_ID` | 긴 UUID 형태 문자열 | b-7 |
| `ASC_KEY_ID` | 10자리 영숫자 | b-7 |
| `ASC_KEY_CONTENT` | `.p8` 파일을 **base64로 바꾼 한 줄** | b-7 파일 + 아래 명령 |
| `MATCH_GIT_URL` | `https://github.com/slzlrns-byte/medi-certs` | e-4 |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `사용자이름:PAT` 를 **base64로 바꾼 한 줄** | e-7 + 아래 명령 |
| `MATCH_PASSWORD` | **본인이 지금 새로 정하는 암호** | 아래 설명 |

### ASC_KEY_CONTENT — .p8 을 base64 로

윈도우 PowerShell 을 열고(시작 → `powershell`), 아래를 **파일 경로만 본인 것으로 바꿔서** 붙여넣습니다.

```powershell
$p8 = "C:\Users\com\Downloads\AuthKey_ABCD123456.p8"
[Convert]::ToBase64String([IO.File]::ReadAllBytes($p8)) | Set-Clipboard
```

클립보드에 긴 한 줄이 담깁니다. 시크릿 값 칸에 그대로 붙여넣으세요.
(줄바꿈이 들어가면 안 됩니다. `Set-Clipboard` 를 쓰면 안전합니다.)

### MATCH_GIT_BASIC_AUTHORIZATION — 사용자이름:PAT 를 base64 로

```powershell
$user = "slzlrns-byte"
$pat  = "ghp_여기에_토큰"
[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$user`:$pat")) | Set-Clipboard
```

### MATCH_PASSWORD

애플에서 받는 값이 아니라 **본인이 새로 정하는 암호**입니다.
인증서를 암호화하는 열쇠라서, 잃어버리면 `medi-certs` 안의 인증서를 못 열고
**인증서를 폐기하고 처음부터 다시 발급**해야 합니다.
20자 이상 무작위 문자열을 만들어 **비밀번호 관리자에 저장**하세요.

```powershell
-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 28 | ForEach-Object { [char]$_ }) | Set-Clipboard
```

---

## g. 실제로 돌려 보기

### g-1. CI 초록불 확인

1. 저장소 → **Actions** 탭 → 왼쪽 **CI**.
2. 최근 실행이 초록 체크면 코드가 컴파일되고 테스트가 통과한 것입니다.
3. 빨간 X 면 실행을 눌러 어느 단계에서 멈췄는지 봅니다. **여기가 빨간 동안에는 h로 가지 마세요.**

### g-2. 인증서 첫 발급 + TestFlight 업로드

1. **Actions** → 왼쪽 **TestFlight** → 오른쪽 **Run workflow** 버튼.
2. **첫 실행에서만** `first_run` 체크박스를 **켭니다**.
   (`medi-certs` 가 비어 있으니 인증서를 새로 만들어 넣어야 합니다.)
3. **Run workflow** 를 누릅니다. 15~25분 걸립니다.
4. 두 번째 실행부터는 `first_run` 을 **끈 채로** 실행하세요.
   켜 두면 인증서를 또 발급해 기존 것이 무효화될 수 있습니다.

### g-3. TestFlight 에서 받기

1. App Store Connect → 나의 앱 → 더잔잔 → **TestFlight** 탭.
2. 빌드가 "처리 중"(Processing)으로 뜹니다. **10~30분** 기다립니다.
3. 처리가 끝나면 **수출 규정 준수** 질문이 뜰 수 있습니다.
   앱이 `ITSAppUsesNonExemptEncryption = false` 를 이미 선언하고 있어서
   보통은 자동으로 넘어갑니다. 물어보면 **"아니오"** 를 고르세요.
4. 왼쪽 **내부 테스팅**(Internal Testing) → 그룹 **+** → 이름 `내부` →
   **테스터 추가** → 본인 애플 ID 선택 → 저장.
5. 아이폰에서 App Store에서 **TestFlight** 앱을 설치하고 같은 애플 ID로 로그인합니다.
6. TestFlight 앱에 `더잔잔` 이 뜹니다. **설치**를 누릅니다.
7. **워치 앱**은 따로 받지 않습니다. 아이폰의 **Watch** 앱 → 아래로 스크롤 →
   `더잔잔` → **Apple Watch에서 App 보기** 를 켜면 손목에 설치됩니다.

---

## h. 자주 막히는 지점

| 증상 | 원인 | 해결 |
| --- | --- | --- |
| `Could not find profile...` / match 가 아무것도 못 찾음 | `medi-certs` 가 비어 있는데 readonly 모드로 돌았다 | **Run workflow** 에서 `first_run` 을 켜고 다시 실행 |
| `Authentication failed` (git) | `MATCH_GIT_BASIC_AUTHORIZATION` 이 잘못됐다 | `사용자이름:PAT` 를 base64 한 값인지, 줄바꿈이 섞이지 않았는지 확인. PAT 에 `repo` 권한이 있는지 확인 |
| `Invalid curve name` / `Could not create API key` | `ASC_KEY_CONTENT` 가 base64가 아니거나 줄바꿈이 섞였다 | PowerShell `Set-Clipboard` 방식으로 다시 넣기 |
| `No signing certificate "Apple Distribution" found` | 배포 인증서가 없다 | `first_run` 켜고 실행. 이미 3개(최대치)면 developer.apple.com 에서 안 쓰는 인증서를 폐기 |
| `Provisioning profile ... doesn't include the com.apple.developer.icloud-services entitlement` | App ID 에 iCloud capability 를 안 켰다 | c-2 / c-3 을 다시 확인. **워치 App ID 도** iCloud + 컨테이너 체크 필요 |
| `...watchkitapp` 프로파일이 없다고 나옴 | 워치 App ID 를 등록하지 않았다 | c-3 을 하고 `first_run` 으로 다시 실행 |
| `aps-environment` 불일치 | (설정되어 있음) Release 는 production 으로 자동 주입된다 | 손대지 말 것. `project.yml` 의 `APS_ENVIRONMENT` 참고 |
| TestFlight 에 빌드가 안 보임 | 아직 처리 중 | **10~30분** 기다리기. 1시간 넘으면 애플에서 거절 메일이 왔는지 확인 |
| `Missing app icon` 으로 업로드 거절 | 아이콘이 없거나 알파 채널이 있다 | 현재 1024×1024 불투명 PNG 가 들어 있다. 새 아이콘으로 바꿀 때 **투명도를 넣지 말 것** |
| 유료 앱 계약 미체결 경고 | 구독 상품을 만들려면 계약이 필요 | App Store Connect → 비즈니스 → 유료 앱 계약. TestFlight 만 할 거면 무시 가능 |
| CI 는 초록인데 TestFlight 는 빨강 | 시크릿 문제일 가능성이 높다 | 워크플로 첫 단계 "시크릿이 다 있는지 먼저 확인" 의 메시지를 볼 것 |

---

## 참고 · 이 저장소가 이미 해 둔 것

- 번들 ID, 컨테이너 이름, entitlements 는 코드에 박혀 있으니 **위 문서의 문자열을 정확히** 쓰세요.
- entitlements 는 Debug/Release 양쪽 구성에 모두 연결돼 있고, CI가 매번 그걸 검사합니다.
- 빌드 번호는 워크플로 실행 번호(`GITHUB_RUN_NUMBER`)로 자동 증가합니다. 손댈 필요 없습니다.
- 버전(`0.1.0`)은 `project.yml` 의 `MARKETING_VERSION` 에서 올립니다.

---

## CI 분(minute) 아끼기

**macOS 러너는 분당 10배로 청구됩니다.** 비공개 저장소 무료 한도는 월 2,000분이고,
CI 한 번이 5~8분이면 **50~80분**이 깎입니다. 2026-08-26 에 하루 스무 번 넘게 돌려
한도를 소진한 적이 있습니다.

| 워크플로 | 러너 | 실제 시간 | 깎이는 분 | 언제 도는가 |
| --- | --- | --- | --- | --- |
| `ci.yml` · 순수 로직 (리눅스) | ubuntu | ~2분 | **2분** | main push · PR · 수동 |
| `ci.yml` · 빌드와 테스트 | macos-15 | 5~8분 | **50~80분** | 위와 같음, 단 문서·데이터만 바뀌면 건너뜀 |
| `screenshots.yml` | macos-15 | 7~9분 | **70~90분** | `screenshots.yml` 을 일부러 건드릴 때만 |

지키는 규칙:

1. **순수 로직은 리눅스에서 본다.** JanjanCore 는 Foundation 만 쓰므로 우분투에서
   그대로 돕니다. macOS 는 시뮬레이터가 정말 필요한 것만 맡습니다.
2. **문서·데이터만 바뀌면 안 돌린다.** `docs/`, `data/`, `*.md` 는 `paths-ignore` 입니다.
3. **커밋마다 부르지 않는다.** 작업을 묶어 한 번만 돌립니다.
4. **화면 찍기는 손으로만.** 가장 비싸므로 자동으로 돌지 않게 해 두었습니다.

한도가 모자라면 GitHub → Settings → Billing and licenses → Plans and usage 에서
남은 분과 지출 한도를 확인하세요.
