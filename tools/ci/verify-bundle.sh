#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
bundle=${1:-"$project_root/build/LittleSwitch.app"}
binary="$bundle/Contents/MacOS/LittleSwitch"
info="$bundle/Contents/Info.plist"
icon="$bundle/Contents/Resources/AppIcon.icns"
sparkle_framework="$bundle/Contents/Frameworks/Sparkle.framework"

test -x "$binary"
# A freshly stamped Git tag does not prove that the executable is fresh.
# Mach-O UUIDs survive rpath edits and signing, unlike whole-file checksums.
binary_path=$("$project_root/tools/swift-release.sh" --show-bin-path)
release_binary="$binary_path/LittleSwitch"
test -x "$release_binary"
release_uuid=$(xcrun dwarfdump --uuid "$release_binary")
bundle_uuid=$(xcrun dwarfdump --uuid "$binary")
release_uuid=$(printf '%s\n' "$release_uuid" | /usr/bin/awk '$1 == "UUID:" && $3 == "(arm64)" { print $2 }')
bundle_uuid=$(printf '%s\n' "$bundle_uuid" | /usr/bin/awk '$1 == "UUID:" && $3 == "(arm64)" { print $2 }')
if [ -z "$release_uuid" ] || [ "$release_uuid" != "$bundle_uuid" ]; then
    echo "The bundle executable does not match the current release product: $release_binary" >&2
    exit 1
fi
for target in LittleSwitchCore LittleSwitchUI; do
    resource_bundle="$binary_path/LittleSwitch_$target.bundle"
    if [ ! -d "$resource_bundle" ]; then
        echo "Swift release resource bundle not found at $resource_bundle" >&2
        exit 1
    fi
done
for resource_bundle in "$binary_path"/*.bundle; do
    test -d "$resource_bundle" || continue
    bundled_resource="$bundle/Contents/Resources/${resource_bundle##*/}"
    if ! diff -qr "$resource_bundle" "$bundled_resource"; then
        echo "Resource bundle does not match the current release product: $bundled_resource" >&2
        exit 1
    fi
done
runtime_libraries=$(xcrun swift-stdlib-tool --print --platform macosx \
    --scan-executable "$binary" --scan-folder "$bundle/Contents/Frameworks")
printf '%s\n' "$runtime_libraries" | while IFS= read -r library; do
    test -n "$library" || continue
    bundled_library="$bundle/Contents/Frameworks/${library##*/}"
    if [ ! -f "$bundled_library" ]; then
        echo "Required Swift runtime is missing from the bundle: $bundled_library" >&2
        exit 1
    fi
done
/usr/bin/plutil -lint "$info" >/dev/null

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")" = "com.alfredlabs.littleswitch"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$info")" = "AppIcon.icns"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info")" = "14.0"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$info")" = "true"
test "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$info")" = "https://raw.githubusercontent.com/alfred-labs/little-switch/main/packaging/appcast.xml"
test "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info")" = "EjsuvLX03eR7UK3zvF7RzNM0U/0461gxnm1Lo8mi5cg="
test "$(xcrun lipo -archs "$binary")" = "arm64"
"$project_root/tools/ci/verify-app-icon.sh" "$icon"

# Sparkle rides inside the bundle and the executable must find it there.
test -d "$sparkle_framework"
if ! xcrun otool -l "$binary" | /usr/bin/grep -Fq 'path @executable_path/../Frameworks'; then
    echo "The executable lacks the bundle Frameworks rpath" >&2
    exit 1
fi

if xcrun otool -L "$binary" | /usr/bin/grep -q WebKit; then
    echo "The application must not link WebKit" >&2
    exit 1
fi
if find "$bundle" -type f -name '*.js' | /usr/bin/grep -q .; then
    echo "The application bundle must not contain JavaScript" >&2
    exit 1
fi

test -f "$bundle/Contents/Resources/LICENSE"
test -f "$bundle/Contents/Resources/THIRD_PARTY_NOTICES.md"
test -f "$bundle/Contents/Resources/Licenses/hummingbird/LICENSE.txt"
test -f "$bundle/Contents/Resources/Licenses/async-http-client/LICENSE.txt"
test -f "$bundle/Contents/Resources/Licenses/swift-nio/LICENSE.txt"
cmp "$project_root/Vendor/OrderedJSON/LICENSE" \
    "$bundle/Contents/Resources/Licenses/ordered-json/LICENSE"
for sdk in anthropic openai; do
    cmp "$project_root/schemas/upstream/notices/$sdk.LICENSE" \
        "$bundle/Contents/Resources/Licenses/official-sdk-contracts/$sdk.LICENSE"
done
echo "Verified $bundle"
