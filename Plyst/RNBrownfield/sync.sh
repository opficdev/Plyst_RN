#!/bin/sh

set -eu

package_directory="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
source_directory="$package_directory/../../rn/ios/.brownfield/package/build"
destination_directory="$package_directory/Frameworks"

rm -rf "$destination_directory"
mkdir -p "$destination_directory"
cp -RL "$source_directory"/*.xcframework "$destination_directory"/
