#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_directory/common.sh"
release_initialize "$script_directory/../.."

identity=$(resolve_release_identity)
require_developer_id_application "$identity"

LITTLE_SWITCH_SIGN_IDENTITY=$identity "$app_builder"
"$bundle_verifier"
"$codesign" --verify --deep --strict --verbose=2 "$bundle"

version=$(release_version)
dmg=$(release_dmg_path)
/bin/mkdir -p "$dist_directory"

stage=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/little-switch-dmg.XXXXXX")
temporary_dmg=$dist_directory/.LittleSwitch-$version-arm64.$$.dmg

cleanup() {
    if [ -d "$stage" ]; then
        /bin/rm -rf "$stage"
    fi
    if [ -f "$temporary_dmg" ]; then
        /bin/rm -f "$temporary_dmg"
    fi
}
trap cleanup EXIT HUP INT TERM

"$ditto" "$bundle" "$stage/LittleSwitch.app"
/bin/ln -s /Applications "$stage/Applications"
"$hdiutil" create -srcfolder "$stage" -volname "LittleSwitch $version" -format UDZO -ov "$temporary_dmg"
"$codesign" --force --timestamp --sign "$identity" --identifier com.alfredlabs.littleswitch.dmg "$temporary_dmg"
"$codesign" --verify --strict --verbose=2 "$temporary_dmg"
/bin/mv -f "$temporary_dmg" "$dmg"

printf '%s\n' "$dmg"
