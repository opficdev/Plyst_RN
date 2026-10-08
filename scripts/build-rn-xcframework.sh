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

# PlystBridge pod는 BrownfieldLib에 정적으로 링크되어 심볼도 BrownfieldLib에서 제공합니다.
# 중복 링크를 피하면서 import할 수 있도록 모듈과 헤더만 담고 빈 정적 라이브러리를 사용합니다.
bridge_directory=$(mktemp -d)
expected_frameworks_file=
actual_frameworks_file=
trap 'rm -rf "$bridge_directory"; rm -f "$expected_frameworks_file" "$actual_frameworks_file"' EXIT HUP INT TERM

bridge_headers_directory=$repository_root/rn/modules/plyst-bridge/ios
for header in "$bridge_headers_directory"/*.h; do
	if ! [ -f "$header" ]; then
		printf '오류: PlystBridge 공개 헤더가 없습니다: %s\n' "$header" >&2
		exit 1
	fi
done

for platform in iphoneos iphonesimulator; do
	products=$repository_root/rn/ios/.brownfield/build/Build/Products/$configuration-$platform/PlystBridge
	for directory in "$products" "$products/PlystBridge.swiftmodule"; do
		if ! [ -d "$directory" ]; then
			printf '오류: PlystBridge 빌드 산출물 디렉터리가 없습니다: %s\n' "$directory" >&2
			exit 1
		fi
	done
	for header in "$products/PlystBridge-umbrella.h" "$products/Swift Compatibility Header/PlystBridge-Swift.h"; do
		if ! [ -f "$header" ]; then
			printf '오류: PlystBridge 빌드 헤더가 없습니다: %s\n' "$header" >&2
			exit 1
		fi
	done

	architectures=arm64
	suffix=
	if [ "$platform" = iphonesimulator ]; then
		architectures='arm64 x86_64'
		suffix=-simulator
	fi
	for architecture in $architectures; do
		for extension in swiftmodule swiftdoc; do
			module=$products/PlystBridge.swiftmodule/$architecture-apple-ios$suffix.$extension
			if ! [ -f "$module" ]; then
				printf '오류: PlystBridge Swift 모듈 파일이 없습니다: %s\n' "$module" >&2
				exit 1
			fi
		done
	done

	framework=$bridge_directory/$platform/PlystBridge.framework
	mkdir -p "$framework/Headers" "$framework/Modules"
	cp "$bridge_headers_directory"/*.h "$products/PlystBridge-umbrella.h" \
		"$products/Swift Compatibility Header/PlystBridge-Swift.h" "$framework/Headers/"
	cp -R "$products/PlystBridge.swiftmodule" "$framework/Modules/"
	cat > "$framework/Modules/module.modulemap" <<'EOF'
framework module PlystBridge {
  umbrella header "PlystBridge-umbrella.h"

  export *
  module * { export * }
}

module PlystBridge.Swift {
  header "PlystBridge-Swift.h"
  requires objc
}
EOF
	cat > "$framework/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>PlystBridge</string>
	<key>CFBundleIdentifier</key><string>org.cocoapods.PlystBridge</string>
	<key>CFBundleName</key><string>PlystBridge</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>1.0.0</string>
	<key>CFBundleVersion</key><string>1.0.0</string>
	<key>MinimumOSVersion</key><string>15.1</string>
</dict>
</plist>
EOF
	set --
	for architecture in $architectures; do
		object=$bridge_directory/$platform/$architecture.o
		library=$bridge_directory/$platform/$architecture.a
		printf '\n' | xcrun clang -x c -c - -o "$object" -target "$architecture-apple-ios15.1$suffix"
		xcrun libtool -static -o "$library" "$object"
		set -- "$@" "$library"
	done
	if [ "$platform" = iphonesimulator ]; then
		xcrun lipo -create "$@" -output "$framework/PlystBridge"
	else
		cp "$1" "$framework/PlystBridge"
	fi
done

rm -rf "$build_directory/PlystBridge.xcframework"
xcodebuild -create-xcframework \
	-framework "$bridge_directory/iphoneos/PlystBridge.framework" \
	-framework "$bridge_directory/iphonesimulator/PlystBridge.framework" \
	-output "$build_directory/PlystBridge.xcframework"

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
