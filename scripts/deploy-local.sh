#!/bin/sh

set -eu

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

script_directory=$(CDPATH= cd "$(dirname "$0")" && pwd)
repository_root=$(CDPATH= cd "$script_directory/.." && pwd)
lane=${1:-}
secrets_file=${SECRETS_FILE:-$repository_root/fastlane/secrets.json}
project_file="$repository_root/Plyst/Plyst.xcodeproj/project.pbxproj"
secret_keys="APP_STORE_TEAM_ID ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_CONTENT MATCH_GIT_URL MATCH_PASSWORD MATCH_GIT_BASIC_AUTHORIZATION"

case "$lane" in
	check | testflight_build_only | deploy_testflight | appstore_build_only | deploy_appstore | sync_appstore_profiles) ;;
	*)
		printf '사용법: %s <check|testflight_build_only|deploy_testflight|appstore_build_only|deploy_appstore|sync_appstore_profiles>\n' "$0" >&2
		exit 1
		;;
esac

if [ ! -f "$secrets_file" ]; then
	printf '오류: 시크릿 파일이 없습니다: %s\n' "$secrets_file" >&2
	printf 'fastlane/secrets.example.json을 fastlane/secrets.json으로 복사해 값을 채우세요.\n' >&2
	exit 1
fi

if ! parse_error=$(plutil -convert json -o /dev/null "$secrets_file" 2>&1); then
	printf '오류: 시크릿 파일이 올바른 JSON이 아닙니다.\n%s\n' "$parse_error" >&2
	exit 1
fi

missing_keys=
for key in $secret_keys; do
	value=$(plutil -extract "$key" raw -o - "$secrets_file" 2>/dev/null || :)
	if [ -z "$value" ]; then
		missing_keys="$missing_keys $key"
		continue
	fi
	export "$key=$value"
done

if [ -n "$missing_keys" ]; then
	printf '오류: 시크릿 파일에서 비었거나 없는 키:%s\n' "$missing_keys" >&2
	exit 1
fi

# 배포 환경을 읽기만 하며 확인함
# 시크릿 값과 인증 헤더는 출력하지 않고 파일과 키체인을 바꾸지 않음
if [ "$lane" = check ]; then
	check_failed=

	fail_check() {
		printf '실패: %s\n' "$1" >&2
		check_failed=1
	}

	if ! xcodebuild -version 2>/dev/null | head -n 1 | grep -q '^Xcode 27'; then
		fail_check 'Xcode 27이 선택되어 있지 않습니다. xcodebuild -version과 xcode-select를 확인하세요.'
	fi

	if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
		fail_check 'Xcode 첫 실행 설정이 끝나지 않았습니다. sudo xcodebuild -runFirstLaunch를 실행하세요.'
	fi

	if [ "$(node --version 2>/dev/null)" != "v$(mise current node 2>/dev/null)" ]; then
		fail_check '.mise.toml에 지정한 Node가 실행되지 않습니다. make deploy-setup을 실행하세요.'
	fi

	if ! command -v pod >/dev/null 2>&1; then
		fail_check 'CocoaPods(pod)가 설치되어 있지 않습니다.'
	fi

	if ! (cd "$repository_root" && bundle check >/dev/null 2>&1); then
		fail_check 'Bundler gem이 설치되어 있지 않습니다. make deploy-setup을 실행하세요.'
	fi

	if ! printf '%s' "$ASC_KEY_CONTENT" | base64 -D 2>/dev/null | openssl pkey -noout >/dev/null 2>&1; then
		fail_check 'ASC_KEY_CONTENT가 올바른 Base64 .p8 키가 아닙니다.'
	fi

	# 인증 헤더는 명령줄 인자가 아닌 환경 변수로 넘김
	if ! GIT_TERMINAL_PROMPT=0 \
		GIT_CONFIG_COUNT=1 \
		GIT_CONFIG_KEY_0=http.extraheader \
		GIT_CONFIG_VALUE_0="Authorization: Basic $MATCH_GIT_BASIC_AUTHORIZATION" \
		git ls-remote --exit-code "$MATCH_GIT_URL" HEAD >/dev/null 2>&1; then
		fail_check 'MATCH_GIT_URL 저장소에 접근할 수 없습니다. MATCH_GIT_URL과 MATCH_GIT_BASIC_AUTHORIZATION을 확인하세요.'
	fi

	if [ -n "$check_failed" ]; then
		exit 1
	fi

	printf '배포 환경 확인을 모두 통과했습니다.\n'
	exit 0
fi

# 오래 걸리는 XCFramework 빌드 전에 Fastlane 실행 환경을 확인함
if ! (cd "$repository_root" && bundle check >/dev/null 2>&1); then
	printf '오류: Bundler gem이 설치되어 있지 않습니다. 저장소 루트에서 bundle install을 실행하세요.\n' >&2
	exit 1
fi

export ASC_KEY_PATH="$repository_root/fastlane/AuthKey.p8"
export SPACESHIP_CONNECT_API_IN_HOUSE=false
# Fastfile이 로컬 실행에서도 수동 서명 설정을 적용하도록 알림
export LOCAL_DEPLOY=true

project_backup=

# 성공과 실패 및 인터럽트 모두에서 API 키 파일을 지우고 프로젝트 파일을 되돌림
cleanup() {
	rm -f "$ASC_KEY_PATH"
	if [ -n "$project_backup" ] && [ -f "$project_backup" ]; then
		cp "$project_backup" "$project_file"
		rm -f "$project_backup"
	fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 프로파일 동기화는 앱을 빌드하지 않으므로 XCFramework와 프로젝트 파일을 다루지 않음
if [ "$lane" != sync_appstore_profiles ]; then
	# 배포 빌드는 입력 해시와 관계없이 처음부터 만듦
	RN_XCFRAMEWORK_CLEAN=1 make -C "$repository_root" rn-xcframework RN_CONFIGURATION=Release

	project_backup=$(mktemp)
	cp "$project_file" "$project_backup"
fi

(
	umask 077
	printf '%s' "$ASC_KEY_CONTENT" | base64 -D > "$ASC_KEY_PATH"
)

cd "$repository_root"
bundle exec fastlane "$lane"
