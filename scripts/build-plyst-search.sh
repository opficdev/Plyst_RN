#!/bin/sh

# plyst-search pod이 vendored_frameworks로 쓰는 PlystSearchCore.xcframework를 만듦
# pod install 전에 있어야 CocoaPods가 링크 설정을 만듦
# 입력 해시와 실행 환경이 지난 성공 빌드와 같으면 생략
# RN_XCFRAMEWORK_CLEAN이 비어 있지 않으면 항상 처음부터 빌드

set -eu

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

script_directory=$(CDPATH= cd "$(dirname "$0")" && pwd)
repository_root=$(CDPATH= cd "$script_directory/.." && pwd)
crate=$repository_root/modules/plyst-search/rust
# 작업 트리마다 cargo 출력을 따로 두어 다른 트리의 라이브러리를 집지 않게 함
output=$repository_root/modules/plyst-search/build
target_directory=$output/target
framework=$output/PlystSearchCore.xcframework
marker=$output/.inputs

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

inputs="$("$script_directory/rust-inputs.sh" search) $(xcodebuild -version | tr '\n' ' ')simulator_archs=$simulator_archs"
if [ -z "${RN_XCFRAMEWORK_CLEAN:-}" ] \
	&& [ -f "$marker" ] && [ "$(cat "$marker")" = "$inputs" ] \
	&& [ -d "$framework" ]; then
	printf '[plyst-search] path=skip\n'
	exit 0
fi

set -- cargo
if command -v mise >/dev/null 2>&1; then
	set -- mise exec -- cargo
fi
# 배포 빌드(RN_XCFRAMEWORK_CLEAN)는 cargo 출력을 쓰지 않음
if [ -n "${RN_XCFRAMEWORK_CLEAN:-}" ]; then
	rm -rf "$target_directory"
fi

simulator_targets=aarch64-apple-ios-sim
case "$simulator_archs" in
	*x86_64*) simulator_targets="$simulator_targets x86_64-apple-ios" ;;
esac
for target in aarch64-apple-ios $simulator_targets; do
	IPHONEOS_DEPLOYMENT_TARGET=15.1 "$@" build \
		--manifest-path "$crate/Cargo.toml" \
		--release \
		--locked \
		--target "$target" \
		--target-dir "$target_directory"
done

library=libplyst_search_core.a
set --
for target in $simulator_targets; do
	set -- "$@" "$target_directory/$target/release/$library"
done
mkdir -p "$output/simulator"
xcrun lipo -create "$@" -output "$output/simulator/$library"
rm -rf "$framework"
xcodebuild -create-xcframework \
	-library "$target_directory/aarch64-apple-ios/release/$library" \
	-library "$output/simulator/$library" \
	-output "$framework" > /dev/null

printf '%s\n' "$inputs" > "$marker"
printf '[plyst-search] path=full\n'
