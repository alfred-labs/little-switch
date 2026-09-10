#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
bundle="$project_root/build/LittleSwitch.app"
binary="$bundle/Contents/MacOS/LittleSwitch"
info="$bundle/Contents/Info.plist"
icon="$bundle/Contents/Resources/AppIcon.icns"
sparkle_framework="$bundle/Contents/Frameworks/Sparkle.framework"

test -x "$binary"
/usr/bin/plutil -lint "$info" >/dev/null

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")" = "com.alfredlabs.littleswitch"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$info")" = "AppIcon.icns"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info")" = "14.0"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$info")" = "true"
test "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$info")" = "https://raw.githubusercontent.com/alfred-labs/little-switch/main/packaging/appcast.xml"
test "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info")" = "EjsuvLX03eR7UK3zvF7RzNM0U/0461gxnm1Lo8mi5cg="
test "$(/usr/bin/lipo -archs "$binary")" = "arm64"
"$project_root/tools/ci/verify-app-icon.sh" "$icon"

# Sparkle rides inside the bundle and the executable must find it there.
test -d "$sparkle_framework"
if ! /usr/bin/otool -l "$binary" | /usr/bin/grep -Fq 'path @executable_path/../Frameworks'; then
    echo "The executable lacks the bundle Frameworks rpath" >&2
    exit 1
fi

if /usr/bin/otool -L "$binary" | /usr/bin/grep -q WebKit; then
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
echo "Verified $bundle"
