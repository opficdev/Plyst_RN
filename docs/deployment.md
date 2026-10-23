# 배포 방법

로컬 Mac에서 TestFlight에 빌드를 올리는 절차와 문제 해결 방법

## 한눈에 보기

- 빌드만 실행: `make testflight-build`
- 빌드 후 TestFlight 업로드: `make testflight`
- 서명 인증서와 프로파일: Fastlane `match`가 읽기 전용으로 가져옴
- 시크릿: `fastlane/secrets.json` 한 파일로 관리
- 번들 ID: `opfic.Plyst`, `opfic.Plyst.ShareExtension`, `opfic.Plyst.WidgetExtension`

## 준비

### 도구

- Xcode 27 (`xcodebuild -version`으로 확인)
- mise로 설치한 Node (`.mise.toml`에 버전 지정)
	- 처음 쓰는 저장소 경로면 `mise trust` 필요
- Ruby gem
	- 저장소 루트에서 한 번 실행하며 워크트리마다 다시 필요

```bash
bundle config set --local path vendor/bundle
```

```bash
bundle install
```

### 시크릿 파일

`fastlane/secrets.example.json`을 복사한 뒤 값 채우기

```bash
cp fastlane/secrets.example.json fastlane/secrets.json
```

| 키 | 내용 |
| --- | --- |
| `APP_STORE_TEAM_ID` | Apple Developer 팀 ID |
| `ASC_KEY_ID` | App Store Connect API 키 ID |
| `ASC_ISSUER_ID` | App Store Connect API Issuer ID |
| `ASC_KEY_CONTENT` | `.p8` 파일을 Base64로 인코딩한 한 줄 |
| `MATCH_GIT_URL` | `match` 인증서 저장소 주소 |
| `MATCH_PASSWORD` | `match` 저장소 암호화 암호 |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `match` 저장소 접근 인증 값 |

- 키 이름은 GitHub Secret 이름과 같음
- `fastlane/secrets.json`은 `.gitignore` 대상이라 커밋되지 않음
- 다른 위치의 파일은 `SECRETS_FILE=/경로/secrets.json make testflight-build`로 지정

`ASC_KEY_CONTENT`는 줄바꿈 없이 한 줄이어야 함

```bash
base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '\n'
```

## 실행

### 빌드만 실행

```bash
make testflight-build
```

- 서명된 IPA 생성 후 IPA 내용 검증까지 실행
- 업로드는 하지 않음
- 결과물
	- `fastlane/testflight_build/Plyst.ipa`
	- `fastlane/testflight_build/Plyst.app.dSYM.zip`

### 빌드 후 업로드

```bash
make testflight
```

- `make testflight-build`의 모든 단계 실행 후 `upload_to_testflight`로 업로드
- 이미 만든 IPA만 올리는 `make` 타깃은 없음
- 업로드가 끝나면 Apple의 처리 완료를 기다리지 않고 종료

## 실행 흐름

`scripts/deploy-testflight-local.sh`가 순서대로 실행하는 단계

1. 시크릿 파일 검증
	- 파일이 없거나 JSON이 올바르지 않거나 키가 비어 있으면 키 이름을 알려 주고 종료
2. `bundle check`로 Ruby gem 설치 여부 확인
3. `make rn-xcframework RN_CONFIGURATION=Release`로 Release XCFramework 생성
	- `scripts/build-rn-xcframework.sh`가 프레임워크 `Info.plist` 키를 보충한 뒤 서명
	- 배포 스크립트는 `RN_XCFRAMEWORK_CLEAN=1`을 지정해 입력 해시와 관계없이 처음부터 빌드하고 컴파일 캐시를 쓰지 않음
4. `project.pbxproj` 백업
5. `ASC_KEY_CONTENT`를 `fastlane/AuthKey.p8`로 복원
6. `bundle exec fastlane`으로 레인 실행
7. 종료 시 `AuthKey.p8` 삭제와 `project.pbxproj` 원복
	- 실패하거나 Ctrl+C로 중단해도 실행

Fastlane 레인(`testflight_build_only`, `deploy_testflight`)이 하는 일

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

관측한 소요 시간 (2026-10-13 로컬 실행)

- Release XCFramework 생성: 약 5분
- Archive와 Export: 약 7분

## CI와의 차이

- `.github/workflows/testflight.yml`은 같은 `fastlane/Fastfile`을 사용
- 로컬 실행만 `LOCAL_DEPLOY=true`로 수동 서명 설정을 적용
- 임시 Keychain(`setup_ci`)은 CI에서만 만들며 로컬 Mac의 기본 Keychain은 바꾸지 않음
- 시크릿은 CI에서 GitHub Secret으로 읽고 로컬에서는 `fastlane/secrets.json`으로 읽음

## 업로드 뒤 확인

- 업로드 성공 후에도 Apple이 처리 단계에서 빌드를 거부할 수 있음
- 거부 사유는 App Store Connect 메일로 전달됨
- 처리가 끝나면 TestFlight 빌드 목록에 표시됨

## 문제 해결

| 증상 | 원인 | 해결 |
| --- | --- | --- |
| `시크릿 파일이 올바른 JSON이 아닙니다` | 문자열 안 줄바꿈 또는 문법 오류 | 출력된 줄과 열 위치 확인. `ASC_KEY_CONTENT`는 `tr -d '\n'`으로 한 줄 생성 |
| `비었거나 없는 키` 목록 출력 | 시크릿 파일에서 해당 키가 비어 있음 | 목록의 키 채우기 |
| `Bundler gem이 설치되어 있지 않습니다` | 워크트리에 `vendor/bundle` 없음 | `bundle config set --local path vendor/bundle` 후 `bundle install` |
| `mise ERROR ... not trusted` | 새 경로의 `.mise.toml` 미신뢰 | `mise trust` |
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

- `Makefile`: `testflight-build`, `testflight` 타깃
- `scripts/deploy-testflight-local.sh`: 로컬 실행 스크립트
- `scripts/build-rn-xcframework.sh`: Release XCFramework 생성과 `Info.plist` 보충
- `scripts/rn-xcframework-inputs.sh`: XCFramework 빌드 입력 해시 계산
- `fastlane/Fastfile`: 빌드와 업로드 레인
- `fastlane/secrets.example.json`: 시크릿 파일 양식
- `.github/workflows/testflight.yml`: CI 배포 워크플로
