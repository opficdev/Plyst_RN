#!/bin/sh

set -eu

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

script_directory=$(CDPATH= cd "$(dirname "$0")" && pwd)
repository_root=$(CDPATH= cd "$script_directory/.." && pwd)
configuration=${RN_CONFIGURATION:-Release}

cd "$repository_root/rn"
npm ci
npx expo prebuild --platform ios --clean

node_binary=$(command -v node 2>/dev/null || :)
if command -v mise >/dev/null 2>&1; then
	mise_node_binary=$(mise which node 2>/dev/null || :)
	if [ -n "$mise_node_binary" ]; then
		node_binary=$mise_node_binary
	fi
fi

case "$node_binary" in
	/*) ;;
	*)
		printf '오류: Node 실행 파일의 절대 경로를 찾을 수 없습니다.\n' >&2
		exit 1
		;;
esac

printf 'export NODE_BINARY=%s\n' "$node_binary" > ios/.xcode.env.local
npx brownfield package:ios --scheme BrownfieldLib --configuration "$configuration"

build_directory=$repository_root/rn/ios/.brownfield/package/build
set -- "$build_directory"/*.xcframework
if ! [ -d "$1" ]; then
	printf '오류: 생성된 XCFramework가 없습니다: %s/*.xcframework\n' "$build_directory" >&2
	exit 1
fi

destination=$repository_root/Plyst/Packages/PlystReactNative/Frameworks
mkdir -p "$destination"
rsync -aL --delete --delete-excluded \
	--include='/*.xcframework/' \
	--include='/*.xcframework/***' \
	--exclude='*' \
	"$build_directory/" "$destination/"

find "$destination" -type d -path '*/ios-*/*.framework' ! -path '*maccatalyst*' \
	-exec codesign --force --sign - --timestamp=none {} +

if [ "$configuration" = Release ]; then
	brownfield_xcframework=$destination/BrownfieldLib.xcframework
	if ! [ -d "$brownfield_xcframework" ]; then
		printf '오류: Release 번들을 확인할 수 없습니다: %s\n' "$brownfield_xcframework" >&2
		exit 1
	fi

	main_bundle=$(find "$brownfield_xcframework" -type f \
		-path '*/BrownfieldLib.framework/main.jsbundle' -print | sed -n '1p')
	if [ -z "$main_bundle" ]; then
		printf '오류: Release XCFramework에 main.jsbundle이 없습니다.\n' >&2
		find "$brownfield_xcframework" -type d -name 'BrownfieldLib.framework' \
			-exec sh -c 'for framework do
				printf "누락: %s/main.jsbundle\n" "$framework" >&2
			done' sh {} +
		exit 1
	fi
fi

package_manifest=$repository_root/Plyst/Packages/PlystReactNative/Package.swift
expected_frameworks_file=$(mktemp)
actual_frameworks_file=$(mktemp)
trap 'rm -f "$expected_frameworks_file" "$actual_frameworks_file"' EXIT HUP INT TERM

sed -n '/^let frameworkNames = \[$/,/^\]$/p' "$package_manifest" \
	| sed -n 's/^[[:space:]]*"\([^"]*\)",[[:space:]]*$/\1/p' \
	| LC_ALL=C sort > "$expected_frameworks_file"

for xcframework in "$destination"/*.xcframework; do
	[ -d "$xcframework" ] || continue
	basename "$xcframework" .xcframework
done | LC_ALL=C sort > "$actual_frameworks_file"

if ! cmp -s "$expected_frameworks_file" "$actual_frameworks_file"; then
	printf '오류: Package.swift와 XCFramework 이름이 일치하지 않습니다.\n' >&2
	printf 'Package.swift에만 있는 이름:\n' >&2
	comm -23 "$expected_frameworks_file" "$actual_frameworks_file" | sed 's/^/  /' >&2
	printf '산출물에만 있는 이름:\n' >&2
	comm -13 "$expected_frameworks_file" "$actual_frameworks_file" | sed 's/^/  /' >&2
	exit 1
fi

printf '%s\n' "$configuration" > "$destination/.configuration"
