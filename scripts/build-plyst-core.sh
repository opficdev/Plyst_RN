#!/bin/sh

# Rust 공통 코어를 iOS용 XCFramework와 생성 Swift로 만듦
# 입력 해시와 실행 환경이 지난 성공 빌드와 같으면 생략
# RN_XCFRAMEWORK_CLEAN이 비어 있지 않으면 항상 처음부터 빌드

set -eu

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

script_directory=$(CDPATH= cd "$(dirname "$0")" && pwd)
repository_root=$(CDPATH= cd "$script_directory/.." && pwd)
crate=$repository_root/core
output=$crate/build
target_directory=$output/target
package=$repository_root/Plyst/Packages/PlystCore
frameworks=$package/Frameworks
sources=$package/Sources/PlystCore
marker=$frameworks/.inputs

# CI는 RN_XCFRAMEWORK_SIMULATOR_ARCHS=arm64로 시뮬레이터 x86_64 슬라이스를 생략
# 배포 빌드(RN_XCFRAMEWORK_CLEAN)는 항상 두 아키텍처를 빌드
simulator_archs=${RN_XCFRAMEWORK_SIMULATOR_ARCHS:-arm64 x86_64}
if [ -n "${RN_XCFRAMEWORK_CLEAN:-}" ]; then
	simulator_archs='arm64 x86_64'
fi
case "$simulator_archs" in
	'arm64 x86_64' | arm64) ;;
	*)
		printf '오류: 지원하지 않는 시뮬레이터 아키텍처입니다: %s\n' "$simulator_archs" >&2
		exit 1
		;;
esac

inputs="$("$script_directory/rn-xcframework-inputs.sh" core) $(xcodebuild -version | tr '\n' ' ')simulator_archs=$simulator_archs"
if [ -z "${RN_XCFRAMEWORK_CLEAN:-}" ] \
	&& [ -f "$marker" ] && [ "$(cat "$marker")" = "$inputs" ] \
	&& [ -d "$frameworks/PlystCoreFFI.xcframework" ] && [ -f "$sources/PlystCore.swift" ]; then
	printf '[plyst-core] path=skip\n'
	exit 0
fi

# core/.cargo/config.toml이 읽히도록 크레이트 폴더에서 실행
cd "$crate"
set -- cargo
if command -v mise >/dev/null 2>&1; then
	set -- mise exec -- cargo
fi
# 배포 빌드(RN_XCFRAMEWORK_CLEAN)만 cargo 출력을 지워 처음부터 빌드
# CI는 develop 실행이 저장한 cargo 출력을 복원해 바뀐 크레이트만 다시 컴파일
if [ -n "${RN_XCFRAMEWORK_CLEAN:-}" ]; then
	rm -rf "$output"
fi

simulator_targets=aarch64-apple-ios-sim
case "$simulator_archs" in
	*x86_64*) simulator_targets="$simulator_targets x86_64-apple-ios" ;;
esac
for target in aarch64-apple-ios $simulator_targets; do
	IPHONEOS_DEPLOYMENT_TARGET=17.0 "$@" build \
		--manifest-path "$crate/Cargo.toml" \
		--release \
		--locked \
		--target "$target" \
		--target-dir "$target_directory"
done

library=libplyst_core.a
set --
for target in $simulator_targets; do
	set -- "$@" "$target_directory/$target/release/$library"
done
mkdir -p "$output/simulator"
xcrun lipo -create "$@" -output "$output/simulator/$library"

bindings=$output/bindings
rm -rf "$bindings"
"$script_directory/generate-plyst-core-bindings.sh" swift "$bindings"
headers=$output/headers
rm -rf "$headers"
mkdir -p "$headers"
cp "$bindings/PlystCoreFFI.h" "$bindings/module.modulemap" "$headers/"

rm -rf "$frameworks"
mkdir -p "$frameworks" "$sources"
xcodebuild -create-xcframework \
	-library "$target_directory/aarch64-apple-ios/release/$library" -headers "$headers" \
	-library "$output/simulator/$library" -headers "$headers" \
	-output "$frameworks/PlystCoreFFI.xcframework" > /dev/null
cp "$bindings/PlystCore.swift" "$sources/PlystCore.swift"

printf '%s\n' "$inputs" > "$marker"
printf '[plyst-core] path=full\n'
