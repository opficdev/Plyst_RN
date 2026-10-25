# 배포 방법

로컬 Mac에서 TestFlight와 App Store Connect에 빌드를 올리는 절차와 문제 해결 방법

## 한눈에 보기

- 배포는 로컬 Mac의 `make` 타깃으로만 실행하며 GitHub Actions에는 배포 워크플로가 없음
- 새 Mac 준비: `make deploy-setup`
- 배포 환경 확인: `make deploy-check`
- TestFlight
	- 빌드만 실행: `make testflight-build`
	- 빌드 후 업로드: `make testflight`
- App Store Connect
	- 빌드만 실행: `make appstore-build`
	- 빌드 후 업로드: `make appstore`
- 인증서와 프로파일 생성 및 갱신: `make signing-sync`
- 서명 인증서와 프로파일: Fastlane `match`가 읽기 전용으로 가져옴
- 시크릿: `fastlane/secrets.json` 한 파일로 관리
- 번들 ID: `opfic.Plyst`, `opfic.Plyst.ShareExtension`, `opfic.Plyst.WidgetExtension`

## 새 Mac 준비

### 직접 설치할 것

- Xcode 27 (`xcodebuild -version`으로 확인)
	- 설치 후 라이선스 동의와 `sudo xcodebuild -runFirstLaunch` 필요
	- `xcode-select`가 Xcode 27을 가리켜야 함
- Homebrew, mise, Ruby, CocoaPods
	- CocoaPods 버전은 저장소에 고정되어 있지 않음
- 시크릿 값
	- 저장소 밖 경로로 안전하게 옮겨 와야 함
	- 로그인 키체인이 잠금 해제된 GUI 세션에서 실행해야 함

### `make deploy-setup`

```bash
make deploy-setup
```

- `mise trust`와 `mise install node`로 `.mise.toml`의 Node 설치
- `bundle config set --local path vendor/bundle`과 `bundle install`로 Ruby gem 설치
	- 워크트리마다 다시 필요
- `fastlane/secrets.json`이 없을 때만 `fastlane/secrets.example.json`을 복사
	- 이미 있는 파일은 덮어쓰지 않음
- 저장소 추적 파일은 바꾸지 않음

### 시크릿 파일

`fastlane/secrets.json`에 값 채우기

| 키 | 내용 |
| --- | --- |
| `APP_STORE_TEAM_ID` | Apple Developer 팀 ID |
| `ASC_KEY_ID` | App Store Connect API 키 ID |
| `ASC_ISSUER_ID` | App Store Connect API Issuer ID |
| `ASC_KEY_CONTENT` | `.p8` 파일을 Base64로 인코딩한 한 줄 |
| `MATCH_GIT_URL` | `match` 인증서 저장소 주소 |
| `MATCH_PASSWORD` | `match` 저장소 암호화 암호 |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `match` 저장소 접근 인증 값 |

- `fastlane/secrets.json`은 `.gitignore` 대상이라 커밋되지 않음
- 다른 위치의 파일은 `SECRETS_FILE=/경로/secrets.json make testflight-build`로 지정

`ASC_KEY_CONTENT`는 줄바꿈 없이 한 줄이어야 함

```bash
base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '\n'
```

### `make deploy-check`

```bash
make deploy-check
```

- 읽기만 하며 시크릿 값과 인증 헤더를 출력하지 않고 파일과 키체인을 바꾸지 않음
- 실패한 항목을 모두 출력한 뒤 종료
- 확인하는 항목
	- Xcode 27 선택 여부와 첫 실행 설정
	- `.mise.toml`에 지정한 Node 실행 여부
	- `pod` 설치 여부
	- Ruby gem 설치 여부
	- 시크릿 파일의 존재와 JSON 형식과 키 7개 값
	- `ASC_KEY_CONTENT`가 읽을 수 있는 `.p8` 키인지
	- `MATCH_GIT_URL` 저장소 접근 가능 여부 (네트워크 사용)
- 키체인의 서명 인증서는 확인하지 않음
	- 새 Mac에서는 첫 배포의 `match`가 인증서를 설치함

### 첫 실행

- 새 Mac의 첫 실행은 업로드하지 않는 `make testflight-build`로 시작
	- `MATCH_PASSWORD`, 인증서 설치, 서명, IPA 검증까지 확인
- 첫 `codesign` 때 키 접근 허용 창이 뜨면 허용해야 함
- Apple ID 로그인은 필요 없으며 모든 레인이 App Store Connect API 키를 씀

## 실행

### TestFlight

```bash
make testflight-build
```

- 서명된 IPA 생성 후 IPA 내용 검증까지 실행하고 업로드는 하지 않음
- 결과물
	- `fastlane/testflight_build/Plyst.ipa`
	- `fastlane/testflight_build/Plyst.app.dSYM.zip`

```bash
make testflight
```

- `make testflight-build`의 모든 단계 실행 후 `upload_to_testflight`로 업로드
- 업로드가 끝나면 Apple의 처리 완료를 기다리지 않고 종료

### App Store Connect

```bash
make appstore-build
```

- 서명된 IPA 생성 후 IPA 내용 검증까지 실행하고 업로드는 하지 않음
- 결과물
	- `fastlane/appstore_build/Plyst.ipa`
	- `fastlane/appstore_build/Plyst.app.dSYM.zip`

```bash
make appstore
```

- `make appstore-build`의 모든 단계 실행 후 `upload_to_app_store`로 업로드
- 메타데이터와 스크린샷은 올리지 않으며 심사 제출과 자동 출시도 하지 않음
	- 심사 제출은 App Store Connect에서 직접 실행

### 인증서와 프로파일 갱신

```bash
make signing-sync
```

- App Store 인증서와 세 프로파일을 `match`로 생성하거나 갱신
	- `match` 저장소에 쓰므로 `readonly`를 끈 유일한 실행
- 이미 있는 항목을 강제로 다시 만들려면 `make signing-sync MATCH_FORCE=true`
- 앱을 빌드하지 않으므로 XCFramework 생성과 `project.pbxproj` 백업은 하지 않음

이미 만든 IPA만 올리는 `make` 타깃은 없음

## 실행 흐름

`scripts/deploy-local.sh`가 순서대로 실행하는 단계

1. 모드 검사
	- 허용 모드는 `check`, `testflight_build_only`, `deploy_testflight`, `appstore_build_only`, `deploy_appstore`, `sync_appstore_profiles`
2. 시크릿 파일 검증
	- 파일이 없거나 JSON이 올바르지 않거나 키가 비어 있으면 키 이름을 알려 주고 종료
3. `check` 모드는 환경 확인 후 종료
4. `bundle check`로 Ruby gem 설치 여부 확인
5. `make rn-xcframework RN_CONFIGURATION=Release`로 Release XCFramework 생성 (`sync_appstore_profiles` 제외)
	- `scripts/build-rn-xcframework.sh`가 프레임워크 `Info.plist` 키를 보충한 뒤 서명
	- 배포 스크립트는 `RN_XCFRAMEWORK_CLEAN=1`을 지정해 입력 해시와 관계없이 처음부터 빌드하고 컴파일 캐시를 쓰지 않음
6. `project.pbxproj` 백업 (`sync_appstore_profiles` 제외)
7. `ASC_KEY_CONTENT`를 `fastlane/AuthKey.p8`로 복원
8. `bundle exec fastlane`으로 레인 실행
9. 종료 시 `AuthKey.p8` 삭제와 `project.pbxproj` 원복
	- 실패하거나 Ctrl+C로 중단해도 실행

Fastlane 레인(`testflight_build_only`, `deploy_testflight`, `appstore_build_only`, `deploy_appstore`)이 하는 일

- Release XCFramework 여부 확인
- App Store Connect에서 최신 빌드 번호를 읽어 1을 더한 번호를 `CURRENT_PROJECT_VERSION`으로 주입
- `match`로 App Store 인증서와 프로파일 가져오기
- 앱, Share Extension, Widget Extension에 수동 서명 설정 적용
- `Plyst/Packages/PlystReactNative/Frameworks`의 모든 XCFramework를 `match` 프로파일의 인증서로 서명
	- `match`가 설치한 프로파일에 들어 있는 인증서와 같은 키체인 인증서만 사용
	- 키체인에 다른 Apple Distribution 인증서가 있어도 인증서 출처는 `match` 저장소 하나로 유지
	- App Store Connect가 널리 쓰이는 서드파티 SDK에 서명을 요구하기 때문
- Archive 후 Export
- IPA의 번들 ID, `ITSAppUsesNonExemptEncryption`, RN 프레임워크와 `main.jsbundle` 검증

로컬 실행 강제

- 모든 Fastlane 레인은 `before_all`에서 `LOCAL_DEPLOY=true`를 확인하고 `CI`가 설정되어 있으면 멈춤
- `scripts/deploy-local.sh`만 `LOCAL_DEPLOY=true`를 설정하므로 `fastlane`을 직접 실행하면 거부됨
	- 스크립트의 정리 단계 없이 서명 설정이 `project.pbxproj`에 남는 경로를 막기 위함

관측한 소요 시간 (2026-10-13 로컬 실행, TestFlight)

- Release XCFramework 생성: 약 5분
- Archive와 Export: 약 7분

## 버전과 태그

- 앱 버전은 앱 타깃의 `MARKETING_VERSION`을 읽고 빌드 번호는 App Store Connect 최신값에 1을 더함
- `.github/workflows/release.yml`은 `develop`에서 `main`으로 병합된 PR의 태그와 GitHub Release만 만들며 배포와 독립적
- 권장 순서
	- `MARKETING_VERSION`을 올린 커밋을 병합
	- 그 커밋에서 `make appstore` 실행

## 업로드 뒤 확인

- 업로드 성공 후에도 Apple이 처리 단계에서 빌드를 거부할 수 있음
- 거부 사유는 App Store Connect 메일로 전달됨
- 처리가 끝나면 TestFlight 빌드 목록 또는 App Store Connect의 빌드 목록에 표시됨

## 문제 해결

| 증상 | 원인 | 해결 |
| --- | --- | --- |
| `Run through make: ...` | `fastlane`을 직접 실행했거나 `CI`가 설정된 환경 | `make` 타깃으로 실행하고 `CI` 환경 변수 제거 |
| `시크릿 파일이 올바른 JSON이 아닙니다` | 문자열 안 줄바꿈 또는 문법 오류 | 출력된 줄과 열 위치 확인. `ASC_KEY_CONTENT`는 `tr -d '\n'`으로 한 줄 생성 |
| `비었거나 없는 키` 목록 출력 | 시크릿 파일에서 해당 키가 비어 있음 | 목록의 키 채우기 |
| `Bundler gem이 설치되어 있지 않습니다` | 워크트리에 `vendor/bundle` 없음 | `make deploy-setup` |
| `mise ERROR ... not trusted` | 새 경로의 `.mise.toml` 미신뢰 | `make deploy-setup` 또는 `mise trust` |
| `CocoaPods(pod)가 설치되어 있지 않습니다` | 새 Mac에 `pod` 없음 | CocoaPods 설치 |
| `MATCH_GIT_URL 저장소에 접근할 수 없습니다` | 주소 오류 또는 인증 값 오류 | `MATCH_GIT_URL`과 `MATCH_GIT_BASIC_AUTHORIZATION` 확인 |
| `The keychain has no signing identity ...` | 키체인에 `match` 프로파일의 인증서 없음 | `match` 설치가 끝났는지 확인하고 키 접근 허용 창에서 허용 |
| `make: No rule to make target` | 저장소 루트가 아닌 곳에서 실행 | 저장소 루트로 이동 |
| `exportArchive ... expected one {} but found app-store` | 서명 설정 저장 때 확장 임베드 위치(`dstSubfolder`)가 지워져 확장이 앱의 `PlugIns` 밖에 설치됨 | `fastlane/Fastfile` 최상단의 `dst_subfolder` 속성 등록 유지. 프로젝트를 여는 액션보다 앞에 있어야 함 |
| 업로드 오류 90360, 90530 | 프레임워크 `Info.plist`에 `MinimumOSVersion` 없음 | `scripts/build-rn-xcframework.sh`가 보충. XCFramework를 다시 생성 |
| 업로드 오류 90057 | `BrownfieldLib.framework`에 `CFBundleShortVersionString` 없음 | 위와 같음 |
| ITMS-91065 (처리 단계 거부) | 서명이 없는 서드파티 SDK가 앱에 포함됨 | `fastlane/Fastfile`의 `sign_xcframeworks`가 XCFramework를 서명. `match` 프로파일의 인증서가 키체인에 없으면 실행이 중단됨 |
| ITMS-90208 (처리 단계 거부) | `ReactBrownfield`와 `PlystBridge` 스텁의 최소 버전과 `Info.plist`의 `MinimumOSVersion`이 다름 | 스크립트가 앱의 `IPHONEOS_DEPLOYMENT_TARGET`으로 맞춤 |

## 로컬 XCFramework 빌드

`make rn-xcframework`는 입력에 따라 실행 경로를 고름

- 입력 해시는 `scripts/rn-xcframework-inputs.sh`가 계산하고 CI 캐시 키도 같은 값을 씀
	- `Plyst/Plyst/**` 같은 앱 소스는 입력이 아니므로 바뀌어도 다시 빌드하지 않음
- 실행 경로는 마지막에 출력되는 `path=` 값으로 확인
	- `skip`: 입력 해시가 지난 성공 빌드와 같아 아무것도 하지 않음
	- `js`: JS 입력만 바뀌어 `main.jsbundle`만 다시 만들어 교체하고 다시 서명함
	- `full`: 그 밖의 경우로 `rn/ios`를 다시 만들고 두 slice를 빌드함
- `RN_XCFRAMEWORK_CLEAN=1`을 주면 항상 `full`로 실행하고 `npm ci`도 다시 실행함
- 로컬 `full` 빌드는 컴파일 결과를 `~/Library/Caches/Plyst/RNCompilationCache`에 캐시함
	- 위치는 `RN_COMPILATION_CACHE`로 바꿀 수 있음
	- `CI`가 설정되어 있거나 `RN_XCFRAMEWORK_CLEAN=1`이면 캐시를 쓰지 않음
- 단계별 소요 시간은 `[rn-xcframework] stage=...` 줄로 출력됨

## 관련 파일

- `Makefile`: `deploy-setup`, `deploy-check`, `testflight-build`, `testflight`, `appstore-build`, `appstore`, `signing-sync` 타깃
- `scripts/deploy-local.sh`: 로컬 실행 스크립트
- `scripts/build-rn-xcframework.sh`: Release XCFramework 생성과 `Info.plist` 보충
- `scripts/rn-xcframework-inputs.sh`: XCFramework 빌드 입력 해시 계산
- `fastlane/Fastfile`: 빌드와 업로드 레인
- `fastlane/secrets.example.json`: 시크릿 파일 양식
