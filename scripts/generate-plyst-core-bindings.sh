#!/bin/sh

# core 크레이트의 메타데이터로 UniFFI 바인딩을 생성
# Swift와 Kotlin이 같은 생성기와 같은 크레이트 소스를 쓰도록 이 스크립트만 사용
#
# 사용법: generate-plyst-core-bindings.sh <swift|kotlin> <출력 폴더의 절대 경로>

set -eu

if [ "$#" -ne 2 ]; then
	printf '사용법: %s <swift|kotlin> <출력 폴더의 절대 경로>\n' "$0" >&2
	exit 1
fi

language=$1
output=$2
script_directory=$(CDPATH= cd "$(dirname "$0")" && pwd)
repository_root=$(CDPATH= cd "$script_directory/.." && pwd)
crate=$repository_root/core
host_target=$crate/build/host

# Gradle 데몬의 PATH에는 mise가 없을 수 있음
PATH=$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin
export PATH

# 생성기가 크레이트 폴더에서 cargo metadata를 실행
cd "$crate"
set --
if command -v mise >/dev/null 2>&1; then
	set -- mise exec --
fi

# 메타데이터만 읽으므로 호스트용 디버그 라이브러리로 충분
"$@" cargo build --manifest-path "$crate/Cargo.toml" --locked --target-dir "$host_target"
"$@" cargo build --manifest-path "$crate/bindgen/Cargo.toml" --locked --target-dir "$host_target"

library=$host_target/debug/libplyst_core.a
mkdir -p "$output"
case "$language" in
	swift)
		"$@" "$host_target/debug/uniffi-bindgen-swift" \
			--swift-sources --headers --modulemap \
			--module-name PlystCoreFFI \
			--modulemap-filename module.modulemap \
			--metadata-no-deps \
			"$library" "$output"
		;;
	kotlin)
		"$@" "$host_target/debug/uniffi-bindgen" generate "$library" \
			--language kotlin \
			--no-format \
			--metadata-no-deps \
			--out-dir "$output"
		;;
	*)
		printf '알 수 없는 언어: %s\n' "$language" >&2
		exit 1
		;;
esac
