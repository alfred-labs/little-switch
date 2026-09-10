#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_directory/common.sh"
release_initialize "$script_directory/../.."

dmg=$(release_dmg_path)
require_release_file "$dmg" "notarized release DMG"

"$hdiutil" verify "$dmg"
"$codesign" --verify --strict --verbose=2 "$dmg"
dmg_signature=$("$codesign" -dvvv "$dmg" 2>&1)
require_signature_metadata "$dmg" com.alfredlabs.littleswitch.dmg "$dmg_signature"
"$xcrun" stapler validate "$dmg"
"$spctl" --assess --type open --context context:primary-signature --verbose=4 "$dmg"

mount_point=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/little-switch-mount.XXXXXX")
mounted=false

cleanup() {
    if [ "$mounted" = true ]; then
        "$hdiutil" detach "$mount_point" >/dev/null 2>&1 || true
    fi
    if [ -d "$mount_point" ]; then
        /bin/rmdir "$mount_point" 2>/dev/null || true
    fi
}
trap cleanup EXIT HUP INT TERM

"$hdiutil" attach -readonly -nobrowse -mountpoint "$mount_point" "$dmg" >/dev/null
mounted=true
delivered_app=$mount_point/LittleSwitch.app
delivered_executable=$delivered_app/Contents/MacOS/LittleSwitch
require_release_file "$delivered_app" "application inside release DMG"
require_release_file "$delivered_executable" "application executable inside release DMG"

"$codesign" --verify --deep --strict --verbose=2 "$delivered_app"
app_signature=$("$codesign" -dvvv "$delivered_app" 2>&1)
require_signature_metadata "$delivered_app" com.alfredlabs.littleswitch "$app_signature"
printf '%s\n' "$app_signature" | /usr/bin/grep -F 'flags=0x10000(runtime)' >/dev/null \
    || release_error "$delivered_app does not enable Hardened Runtime"
if [ "$("$lipo" -archs "$delivered_executable")" != arm64 ]; then
    release_error "$delivered_app is not ARM64-only"
fi
"$spctl" --assess --type exec --verbose=4 "$delivered_app"
"$hdiutil" detach "$mount_point"
mounted=false
/bin/rmdir "$mount_point"

printf 'Verified %s\n' "$dmg"
