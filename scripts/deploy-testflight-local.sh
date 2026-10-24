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
	testflight_build_only | deploy_testflight) ;;
	*)
		printf '사용법: %s <testflight_build_only|deploy_testflight>\n' "$0" >&2
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

# 배포 빌드는 입력 해시와 관계없이 처음부터 만듦
RN_XCFRAMEWORK_CLEAN=1 make -C "$repository_root" rn-xcframework RN_CONFIGURATION=Release

project_backup=$(mktemp)
cp "$project_file" "$project_backup"

(
	umask 077
	printf '%s' "$ASC_KEY_CONTENT" | base64 -D > "$ASC_KEY_PATH"
)

cd "$repository_root"
bundle exec fastlane "$lane"
