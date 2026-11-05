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

inputs="$("$script_directory/rn-xcframework-inputs.sh" core) $(xcodebuild -version | tr '\n' ' ')"
if [ -z "${RN_XCFRAMEWORK_CLEAN:-}" ] \
	&& [ -f "$marker" ] && [ "$(cat "$marker")" = "$inputs" ] \
	&& [ -d "$frameworks/PlystCoreFFI.xcframework" ] && [ -f "$sources/PlystCore.swift" ]; then
	printf '[plyst-core] path=skip\n'
	exit 0
fi

cd "$repository_root"
set -- cargo
if command -v mise >/dev/null 2>&1; then
	set -- mise exec -- cargo
fi
if [ -n "${CI:-}" ] || [ -n "${RN_XCFRAMEWORK_CLEAN:-}" ]; then
	rm -rf "$output"
fi

for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
	IPHONEOS_DEPLOYMENT_TARGET=17.0 "$@" build \
		--manifest-path "$crate/Cargo.toml" \
		--release \
		--locked \
		--target "$target" \
		--target-dir "$target_directory"
done

library=libplyst_core.a
mkdir -p "$output/simulator"
xcrun lipo -create \
	"$target_directory/aarch64-apple-ios-sim/release/$library" \
	"$target_directory/x86_64-apple-ios/release/$library" \
	-output "$output/simulator/$library"

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
