#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
build_root="$project_root/build"
bundle="$build_root/LittleSwitch.app"
icon="$build_root/AppIcon.icns"
version_env="$project_root/packaging/version.env"
sparkle_framework="$project_root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

# shellcheck source=packaging/version.env
. "$version_env"
if [ -z "${MARKETING_VERSION:-}" ] || [ -z "${BUILD_NUMBER:-}" ]; then
    echo "packaging/version.env must define MARKETING_VERSION and BUILD_NUMBER" >&2
    exit 1
fi

cd "$project_root"
"$project_root/tools/swift-release.sh"
binary_path=$("$project_root/tools/swift-release.sh" --show-bin-path)
executable="$binary_path/LittleSwitch"
if [ ! -x "$executable" ]; then
    echo "Swift release product not found at $executable" >&2
    exit 1
fi
for target in LittleSwitchCore LittleSwitchUI; do
    resource_bundle="$binary_path/LittleSwitch_$target.bundle"
    if [ ! -d "$resource_bundle" ]; then
        echo "Swift release resource bundle not found at $resource_bundle" >&2
        exit 1
    fi
done

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents/Frameworks"
"$project_root/tools/generate-app-icon.sh" "$icon"
cp "$executable" "$bundle/Contents/MacOS/LittleSwitch"
chmod 0755 "$bundle/Contents/MacOS/LittleSwitch"
for resource_bundle in "$binary_path"/*.bundle; do
    test -d "$resource_bundle" || continue
    /usr/bin/ditto "$resource_bundle" "$bundle/Contents/Resources/${resource_bundle##*/}"
done

# Sparkle.framework must ride inside the bundle; the executable's rpath has
# to find it there (SwiftPM only emits build-directory rpaths).
if [ ! -d "$sparkle_framework" ]; then
    echo "Sparkle.framework not resolved at $sparkle_framework" >&2
    exit 1
fi
/usr/bin/ditto "$sparkle_framework" "$bundle/Contents/Frameworks/Sparkle.framework"
/bin/sh "$project_root/tools/sparkle-update-copy.sh" apply "$bundle/Contents/Frameworks/Sparkle.framework"
bundled_executable="$bundle/Contents/MacOS/LittleSwitch"
if ! xcrun otool -l "$bundled_executable" | /usr/bin/grep -Fq 'path @executable_path/../Frameworks'; then
    xcrun install_name_tool \
        -add_rpath '@executable_path/../Frameworks' "$bundled_executable"
fi
xcrun swift-stdlib-tool --copy --platform macosx \
    --scan-executable "$bundled_executable" \
    --scan-folder "$bundle/Contents/Frameworks" \
    --destination "$bundle/Contents/Frameworks"

cp "$project_root/packaging/Info.plist" "$bundle/Contents/Info.plist"
build_tag=$(git -C "$project_root" describe --tags --always --dirty 2>/dev/null || true)
if [ -z "$build_tag" ]; then
    build_tag=development
fi
info_plist="$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$info_plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$info_plist"
/usr/libexec/PlistBuddy -c "Set :LSBuildTag $build_tag" "$info_plist"
cp "$icon" "$bundle/Contents/Resources/AppIcon.icns"
cp "$project_root/LICENSE" "$bundle/Contents/Resources/LICENSE"
cp "$project_root/THIRD_PARTY_NOTICES.md" "$bundle/Contents/Resources/THIRD_PARTY_NOTICES.md"

licenses="$bundle/Contents/Resources/Licenses"
mkdir -p "$licenses"
for dependency in "$project_root"/.build/checkouts/*; do
    test -d "$dependency" || continue
    dependency_name=${dependency##*/}
    dependency_licenses="$licenses/$dependency_name"
    mkdir -p "$dependency_licenses"
    found=false
    for license_file in "$dependency"/LICENSE* "$dependency"/NOTICE*; do
        test -f "$license_file" || continue
        cp "$license_file" "$dependency_licenses/"
        found=true
    done
    if [ "$found" = false ]; then
        echo "Missing license for Swift package: $dependency_name" >&2
        exit 1
    fi
done

ordered_json_licenses="$licenses/ordered-json"
mkdir -p "$ordered_json_licenses"
cp "$project_root/Vendor/OrderedJSON/LICENSE" "$ordered_json_licenses/LICENSE"

sdk_licenses="$licenses/official-sdk-contracts"
mkdir -p "$sdk_licenses"
for sdk in anthropic openai; do
    cp "$project_root/schemas/upstream/notices/$sdk.LICENSE" "$sdk_licenses/$sdk.LICENSE"
done

signing_env="$project_root/.signing.env"
if [ ! -f "$signing_env" ]; then
    signing_env="$project_root/.env"
fi
sign_identity=$("$project_root/tools/resolve-signing-identity.sh" "$signing_env")
if [ -n "$sign_identity" ]; then
    for library in "$bundle/Contents/Frameworks/"*.dylib; do
        test -f "$library" || continue
        /usr/bin/codesign --force --options runtime --timestamp \
            --sign "$sign_identity" "$library"
    done
    # Nested code signs innermost-first — Apple's notary validates every
    # helper separately, and codesign does not descend into nested bundles.
    set -- \
        "$bundle/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" \
        "$bundle/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" \
        "$bundle/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" \
        "$bundle/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
    for helper in "$@"; do
        test -e "$helper" || continue
        /usr/bin/codesign --force --options runtime --timestamp \
            --sign "$sign_identity" "$helper"
    done
    /usr/bin/codesign --force --options runtime --timestamp \
        --sign "$sign_identity" "$bundle/Contents/Frameworks/Sparkle.framework"
    /usr/bin/codesign --force --options runtime --timestamp \
        --sign "$sign_identity" "$bundle"
else
    # Resource customization invalidates Sparkle's original seal even in a
    # development build. Reseal without requiring a Developer ID identity.
    xcrun codesign --force --sign - "$bundle/Contents/Frameworks/Sparkle.framework"
fi

echo "$bundle"
