#!/bin/sh

# RN XCFramework 빌드 입력의 해시를 한 곳에서 정의합니다.
# 로컬 빌드 스크립트와 CI 캐시 키가 같은 파일 집합을 쓰도록 이 스크립트의 출력만 사용합니다.
#
# 사용법: rn-xcframework-inputs.sh [lock|native|all|files]
#   lock     rn/package-lock.json의 해시
#   native   의존성과 Pods 구성을 정하는 입력과 plyst-bridge 네이티브 소스 내용의 해시
#   all      native 입력과 JS 번들 입력의 해시 (기본값)
#   files    all에 포함되는 파일 경로 목록

set -eu

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

script_directory=$(CDPATH= cd "$(dirname "$0")" && pwd)
repository_root=$(CDPATH= cd "$script_directory/.." && pwd)
cd "$repository_root"

# 추적 중이거나 무시되지 않은 새 파일 중 작업 트리에 실제로 있는 파일만 모읍니다.
list_files() {
	git ls-files --cached --others --exclude-standard -- "$@" | while IFS= read -r file; do
		if [ -f "$file" ]; then
			printf '%s\n' "$file"
		fi
	done | LC_ALL=C sort
}

content_lines() {
	list_files "$@" | xargs shasum -a 256
}

name_lines() {
	list_files "$@" | sed 's/^/name  /'
}

deployment_target_line() {
	deployment_target=$(sed -n 's/^[[:space:]]*IPHONEOS_DEPLOYMENT_TARGET = \(.*\);$/\1/p' \
		Plyst/Plyst.xcodeproj/project.pbxproj | sort -u)
	case "$deployment_target" in
		'' | *[!0-9.]*)
			printf '오류: 앱의 IPHONEOS_DEPLOYMENT_TARGET이 하나로 정해지지 않았습니다.\n' >&2
			exit 1
			;;
	esac
	printf 'deployment_target  %s\n' "$deployment_target"
}

lock_lines() {
	content_lines rn/package-lock.json
}

# 파일 추가와 삭제는 Pods를 다시 만들어야 하므로 plyst-bridge ios 소스는 이름만 포함합니다.
base_lines() {
	content_lines \
		rn/package.json \
		rn/package-lock.json \
		rn/app.json \
		scripts/build-rn-xcframework.sh \
		scripts/rn-xcframework-inputs.sh \
		Plyst/Packages/PlystReactNative/Package.swift \
		.mise.toml \
		':(exclude,glob)rn/modules/**/ios/**' \
		rn/modules
	name_lines ':(glob)rn/modules/**/ios/**'
	deployment_target_line
}

native_lines() {
	base_lines
	content_lines ':(glob)rn/modules/**/ios/**'
}

bundle_lines() {
	content_lines \
		rn/index.ts \
		rn/App.tsx \
		rn/tsconfig.json \
		':(glob)rn/babel.config.*' \
		':(glob)rn/metro.config.*' \
		rn/src
}

hash_of() {
	"$1" | shasum -a 256 | cut -d ' ' -f 1
}

all_lines() {
	native_lines
	bundle_lines
}

case "${1:-all}" in
	lock) hash_of lock_lines ;;
	native) hash_of native_lines ;;
	all) hash_of all_lines ;;
	files) all_lines | grep -v '^deployment_target' | cut -d ' ' -f 3- ;;
	*)
		printf '사용법: %s [lock|native|all|files]\n' "$0" >&2
		exit 1
		;;
esac
