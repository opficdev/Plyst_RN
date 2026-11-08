#!/bin/sh

# iOS용 Rust 산출물을 만드는 입력의 해시를 한 곳에서 정의
# 로컬 빌드 스크립트와 CI 캐시 키가 같은 파일 집합을 쓰도록 이 스크립트의 출력만 사용
#
# 사용법: rust-inputs.sh [core|search]
#   core     PlystCore 패키지를 만드는 입력의 해시
#   search   PlystSearchCore.xcframework를 만드는 입력의 해시

set -eu

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

script_directory=$(CDPATH= cd "$(dirname "$0")" && pwd)
repository_root=$(CDPATH= cd "$script_directory/.." && pwd)
cd "$repository_root"

# 추적 중이거나 무시되지 않은 새 파일 중 작업 트리에 실제로 있는 파일만 모음
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

deployment_target_line() {
	deployment_target=$(sed -n 's/^[[:space:]]*IPHONEOS_DEPLOYMENT_TARGET = \(.*\);$/\1/p' \
		ios/Plyst.xcodeproj/project.pbxproj | sort -u)
	case "$deployment_target" in
		'' | *[!0-9.]*)
			printf '오류: 앱의 IPHONEOS_DEPLOYMENT_TARGET이 하나로 정해지지 않았습니다.\n' >&2
			exit 1
			;;
	esac
	printf 'deployment_target  %s\n' "$deployment_target"
}

# SwiftLint 버전은 Rust 빌드에 쓰이지 않으므로 .mise.toml에서 제외
mise_line() {
	tools=$(grep -v '^"aqua:realm/SwiftLint"' .mise.toml)
	printf 'mise  %s\n' "$(printf '%s' "$tools" | shasum -a 256 | cut -d ' ' -f 1)"
}

core_lines() {
	content_lines \
		':(exclude)core/tests' \
		core \
		scripts/build-plyst-core.sh \
		scripts/generate-plyst-core-bindings.sh \
		ios/Packages/PlystCore/Package.swift \
		ios/Packages/PlystCore/Sources/PlystCore/PrivacyInfo.xcprivacy
	mise_line
	deployment_target_line
}

# Rust 테스트는 라이브러리에 들어가지 않아 제외
search_lines() {
	content_lines \
		':(exclude)modules/plyst-search/rust/tests' \
		modules/plyst-search/rust \
		scripts/build-plyst-search.sh
	mise_line
}

# 파이프라인 안에서는 exit가 스크립트를 끝내지 못하므로 줄을 먼저 변수에 받아 실패를 전달
hash_of() {
	lines=$("$1")
	printf '%s\n' "$lines" | shasum -a 256 | cut -d ' ' -f 1
}

case "${1:-}" in
	core) hash_of core_lines ;;
	search) hash_of search_lines ;;
	*)
		printf '사용법: %s [core|search]\n' "$0" >&2
		exit 1
		;;
esac
