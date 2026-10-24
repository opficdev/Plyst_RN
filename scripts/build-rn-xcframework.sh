#!/bin/sh

set -eu

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

script_directory=$(CDPATH= cd "$(dirname "$0")" && pwd)
repository_root=$(CDPATH= cd "$script_directory/.." && pwd)
configuration=${RN_CONFIGURATION:-Release}

script_started=$(date +%s)
stage_name=
stage_started=$script_started

# 단계별 소요 시간을 초 단위로 출력함
stage_begin() {
	stage_name=$1
	stage_started=$(date +%s)
}

stage_end() {
	printf '[rn-xcframework] stage=%s status=done seconds=%s\n' \
		"$stage_name" "$(($(date +%s) - stage_started))"
}

stage_skip() {
	printf '[rn-xcframework] stage=%s status=skipped seconds=0\n' "$1"
}

marker_value() {
	if [ -f "$1" ]; then
		sed -n "s/^$2=//p" "$1"
	fi
}

destination=$repository_root/Plyst/Packages/PlystReactNative/Frameworks
inputs_script=$script_directory/rn-xcframework-inputs.sh
inputs_marker=$destination/.inputs
package_manifest=$repository_root/Plyst/Packages/PlystReactNative/Package.swift

# Package.swift의 프레임워크 이름과 산출물 이름이 일치하는지 확인함
verify_framework_names() {
	expected_names=$(mktemp)
	actual_names=$(mktemp)

	sed -n '/^let frameworkNames = \[$/,/^\]$/p' "$package_manifest" \
		| sed -n 's/^[[:space:]]*"\([^"]*\)",[[:space:]]*$/\1/p' \
		| LC_ALL=C sort > "$expected_names"

	for xcframework in "$destination"/*.xcframework; do
		[ -d "$xcframework" ] || continue
		basename "$xcframework" .xcframework
	done | LC_ALL=C sort > "$actual_names"

	if cmp -s "$expected_names" "$actual_names"; then
		rm -f "$expected_names" "$actual_names"
		return 0
	fi
	printf '오류: Package.swift와 XCFramework 이름이 일치하지 않습니다.\n' >&2
	printf 'Package.swift에만 있는 이름:\n' >&2
	comm -23 "$expected_names" "$actual_names" | sed 's/^/  /' >&2
	printf '산출물에만 있는 이름:\n' >&2
	comm -13 "$expected_names" "$actual_names" | sed 's/^/  /' >&2
	rm -f "$expected_names" "$actual_names"
	return 1
}

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

cd "$repository_root/rn"

# 입력 해시와 실행 환경이 지난 성공 빌드와 같으면 단계를 생략함
# JS 입력만 바뀌었으면 main.jsbundle만 다시 만들어 교체함
# RN_XCFRAMEWORK_CLEAN이 비어 있지 않으면 항상 처음부터 빌드함
node_version=$("$node_binary" --version)
environment="$(xcodebuild -version | tr '\n' ' ')node=$node_version configuration=$configuration"
all_hash=$("$inputs_script" all)
native_hash=$("$inputs_script" native)
npm_state="lock=$("$inputs_script" lock) node=$node_version npm=$(npm --version)"
npm_marker=node_modules/.plyst-npm-ci
build_directory=$repository_root/rn/ios/.brownfield/package/build
products_directory=$repository_root/rn/ios/.brownfield/build/Build/Products

# 앱이 쓰는 BrownfieldLib 프레임워크의 main.jsbundle만 Xcode 번들 단계와 같은 환경으로 다시 만듦
# 번들에는 Metro 출력 경로가 들어가므로 전체 빌드와 같은 Products 경로를 그대로 씀
rebuild_bundle() {
	[ "$configuration" = Release ] || return 1
	[ -d "$build_directory/BrownfieldLib.xcframework" ] || return 1

	ios_directory=$repository_root/rn/ios
	entry_file=$("$node_binary" -e "require('expo/scripts/resolveAppEntry')" "$repository_root/rn" ios absolute | tail -n 1)
	cli_path=$("$node_binary" --print "require.resolve('@expo/cli', { paths: [require.resolve('expo/package.json')] })")
	bundle_script=$("$node_binary" --print "require('path').dirname(require.resolve('react-native/package.json')) + '/scripts/react-native-xcode.sh'")

	for platform in iphoneos iphonesimulator; do
		products=$products_directory/$configuration-$platform
		framework=$products/BrownfieldLib.framework
		[ -d "$framework" ] || return 1

		(
			export CONFIGURATION=$configuration
			export PLATFORM_NAME=$platform
			export CONFIGURATION_BUILD_DIR=$products
			export UNLOCALIZED_RESOURCES_FOLDER_PATH=BrownfieldLib.framework
			export PROJECT_DIR=$ios_directory
			export SRCROOT=$ios_directory
			export PODS_ROOT=$ios_directory/Pods
			export PROJECT_ROOT=$repository_root/rn
			export NODE_BINARY=$node_binary
			export ENTRY_FILE=$entry_file
			export CLI_PATH=$cli_path
			export BUNDLE_COMMAND=export:embed
			bash "$bundle_script"
		) > /dev/null 2>&1 || return 1

		# 슬라이스 디렉터리 이름은 simulator 여부로 구분함
		case $platform in
			iphoneos) pattern='*/ios-arm64/BrownfieldLib.framework' ;;
			*) pattern='*/ios-*simulator/BrownfieldLib.framework' ;;
		esac
		slice=$(find "$build_directory/BrownfieldLib.xcframework" -type d -path "$pattern" | sed -n '1p')
		[ -n "$slice" ] || return 1

		# 번들 외에 바뀐 파일이 있으면 교체만으로는 결과가 달라지므로 전체 빌드로 넘어감
		diff -rq -x main.jsbundle -x _CodeSignature -x '*-apple-ios*.swiftmodule' "$framework" "$slice" > /dev/null || return 1
		cp "$framework/main.jsbundle" "$slice/main.jsbundle" || return 1
	done
}

path=full
if [ -z "${RN_XCFRAMEWORK_CLEAN:-}" ] \
	&& [ "$(marker_value "$inputs_marker" environment)" = "$environment" ] \
	&& [ -f "$destination/.configuration" ]; then
	if [ "$(marker_value "$inputs_marker" all)" = "$all_hash" ] && verify_framework_names 2>/dev/null; then
		path=skip
	elif [ "$(marker_value "$inputs_marker" native)" = "$native_hash" ]; then
		path=js
	fi
fi

if [ "$path" = skip ]; then
	printf '[rn-xcframework] path=skip total=%s\n' "$(($(date +%s) - script_started))"
	exit 0
fi

if [ "$path" = js ]; then
	stage_begin bundle-js
	if rebuild_bundle; then
		stage_end
	else
		printf '[rn-xcframework] JS 번들만 교체할 수 없어 전체 빌드로 넘어갑니다.\n'
		path=full
	fi
fi

if [ "$path" = full ]; then
	stage_begin npm-ci
	if [ -f "$npm_marker" ] && [ "$(cat "$npm_marker")" = "$npm_state" ] && [ -z "${RN_XCFRAMEWORK_CLEAN:-}" ]; then
		stage_skip npm-ci
	else
		npm ci
		printf '%s\n' "$npm_state" > "$npm_marker"
		stage_end
	fi

	# 아래 brownfield package:ios가 ios를 다시 만든 뒤 pod install을 한 번 실행하므로 여기서는 설치하지 않음
	stage_begin prebuild
	npx expo prebuild --platform ios --clean --no-install
	printf 'export NODE_BINARY=%s\n' "$node_binary" > ios/.xcode.env.local
	stage_end

	# 로컬 빌드는 컴파일 결과를 저장소 밖에 캐시해 ios가 지워져도 다시 컴파일하지 않음
	# 배포 빌드(RN_XCFRAMEWORK_CLEAN)와 CI는 캐시를 쓰지 않음
	stage_begin package-ios
	# 사전 컴파일 Expo 모듈은 쓰지 않는 모듈까지 별도 프레임워크로 실음
	# Expo 모듈을 소스로 빌드해 BrownfieldLib에 정적으로 합치고 autolinking 제외 설정을 적용함
	export EXPO_USE_PRECOMPILED_MODULES=0
	set -- --scheme BrownfieldLib --configuration "$configuration" --use-prebuilt-expo false
	if [ -z "${CI:-}" ] && [ -z "${RN_XCFRAMEWORK_CLEAN:-}" ]; then
		cache_directory=${RN_COMPILATION_CACHE:-$HOME/Library/Caches/Plyst/RNCompilationCache}
		set -- "$@" --extra-params "COMPILATION_CACHE_ENABLE_CACHING=YES SWIFT_ENABLE_EXPLICIT_MODULES=YES COMPILATION_CACHE_CAS_PATH=$cache_directory COMPILER_INDEX_STORE_ENABLE=NO"
	fi
	npx brownfield package:ios "$@"
	stage_end
else
	stage_skip npm-ci
	stage_skip prebuild
	stage_skip package-ios
fi

set -- "$build_directory"/*.xcframework
if ! [ -d "$1" ]; then
	printf '오류: 생성된 XCFramework가 없습니다: %s/*.xcframework\n' "$build_directory" >&2
	exit 1
fi

stage_begin bridge-xcframework
# PlystBridge pod는 BrownfieldLib에 정적으로 링크되어 심볼도 BrownfieldLib에서 제공함
# 중복 링크를 피하면서 import할 수 있도록 모듈과 헤더만 담고 빈 정적 라이브러리를 사용함
bridge_directory=$(mktemp -d)
trap 'rm -rf "$bridge_directory"' EXIT HUP INT TERM

bridge_headers_directory=$repository_root/rn/modules/plyst-bridge/ios
for header in "$bridge_headers_directory"/*.h; do
	if ! [ -f "$header" ]; then
		printf '오류: PlystBridge 공개 헤더가 없습니다: %s\n' "$header" >&2
		exit 1
	fi
done

for platform in iphoneos iphonesimulator; do
	products=$repository_root/rn/ios/.brownfield/build/Build/Products/$configuration-$platform/PlystBridge/PlystBridge.framework
	for directory in "$products" "$products/Modules/PlystBridge.swiftmodule"; do
		if ! [ -d "$directory" ]; then
			printf '오류: PlystBridge 빌드 산출물 디렉터리가 없습니다: %s\n' "$directory" >&2
			exit 1
		fi
	done
	for header in "$products/Headers/PlystBridge-umbrella.h" "$products/Headers/PlystBridge-Swift.h"; do
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
			module=$products/Modules/PlystBridge.swiftmodule/$architecture-apple-ios$suffix.$extension
			if ! [ -f "$module" ]; then
				printf '오류: PlystBridge Swift 모듈 파일이 없습니다: %s\n' "$module" >&2
				exit 1
			fi
		done
	done

	framework=$bridge_directory/$platform/PlystBridge.framework
	mkdir -p "$framework/Headers" "$framework/Modules"
	cp "$bridge_headers_directory"/*.h "$products/Headers/PlystBridge-umbrella.h" \
		"$products/Headers/PlystBridge-Swift.h" "$framework/Headers/"
	cp -R "$products/Modules/PlystBridge.swiftmodule" "$framework/Modules/"
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
stage_end

stage_begin install-frameworks
mkdir -p "$destination"
rsync -aL --delete --delete-excluded \
	--include='/*.xcframework/' \
	--include='/*.xcframework/***' \
	--exclude='*' \
	"$build_directory/" "$destination/"

# BrownfieldLib의 Info.plist에는 App Store Connect 검증에 필요한 CFBundleShortVersionString이 없음
# Info.plist를 수정하면 서명이 깨지므로 아래 ad-hoc 서명 전에 실행함
find "$destination/BrownfieldLib.xcframework" -type f \
	-path '*/ios-*/BrownfieldLib.framework/Info.plist' ! -path '*maccatalyst*' \
	-exec plutil -replace CFBundleShortVersionString -string 1.0 {} +

# 바이너리가 없는 ReactBrownfield와 PlystBridge에는 Xcode가 앱 배포 대상 버전으로 만든 스텁을 넣음
# 두 프레임워크의 MinimumOSVersion이 스텁의 최소 버전과 다르면 App Store Connect가 ITMS-90208로 거부함
deployment_target=$(sed -n 's/^[[:space:]]*IPHONEOS_DEPLOYMENT_TARGET = \(.*\);$/\1/p' \
	"$repository_root/Plyst/Plyst.xcodeproj/project.pbxproj" | sort -u)
case "$deployment_target" in
	'' | *[!0-9.]*)
		printf '오류: 앱의 IPHONEOS_DEPLOYMENT_TARGET이 하나로 정해지지 않았습니다.\n' >&2
		exit 1
		;;
esac
for name in ReactBrownfield PlystBridge; do
	find "$destination/$name.xcframework" -type f \
		-path "*/ios-*/$name.framework/Info.plist" ! -path '*maccatalyst*' \
		-exec plutil -replace MinimumOSVersion -string "$deployment_target" {} +
done

# 앱에 임베드하는 프레임워크는 Xcode가 스트립하지 않으므로 Release에서 기기 슬라이스의 동적 라이브러리에 있는 디버그 심볼과 로컬 심볼을 지움
# Debug 빌드는 디버그 정보를 유지하려고 건너뜀
# 정적 스텁인 ReactBrownfield와 PlystBridge와 시뮬레이터 슬라이스는 대상이 아님
# 스트립은 서명을 무효로 만들므로 아래 ad-hoc 서명 전에 실행함
if [ "$configuration" = Release ]; then
	for framework in "$destination"/*.xcframework/ios-arm64/*.framework; do
		binary=$framework/$(basename "$framework" .framework)
		if file -b "$binary" | grep -q 'dynamically linked shared library'; then
			# strip이 서명 무효화 경고를 매번 출력하므로 실패했을 때만 출력을 보여 줌
			if ! strip_output=$(xcrun strip -S -x "$binary" 2>&1); then
				printf '오류: 스트립에 실패했습니다: %s\n%s\n' "$binary" "$strip_output" >&2
				exit 1
			fi
		fi
	done
fi

find "$destination" -type d -path '*/ios-*/*.framework' ! -path '*maccatalyst*' \
	-exec codesign --force --sign - --timestamp=none {} +
stage_end

stage_begin verify

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

verify_framework_names || exit 1

printf '%s\n' "$configuration" > "$destination/.configuration"

# 빌드 중 입력이 바뀌었으면 마커를 쓰지 않아 다음 실행이 다시 빌드함
if [ "$("$inputs_script" all)" = "$all_hash" ]; then
	printf 'all=%s\nnative=%s\nenvironment=%s\n' "$all_hash" "$native_hash" "$environment" \
		> "$inputs_marker.tmp"
	mv "$inputs_marker.tmp" "$inputs_marker"
else
	printf '경고: 빌드 중 입력이 바뀌어 입력 마커를 쓰지 않았습니다.\n' >&2
fi
stage_end
printf '[rn-xcframework] path=%s total=%s\n' "$path" "$(($(date +%s) - script_started))"
