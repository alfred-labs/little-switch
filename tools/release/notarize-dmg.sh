#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_directory/common.sh"
release_initialize "$script_directory/../.."

dmg=$(release_dmg_path)
require_release_file "$dmg" "signed release DMG"

profile=${LITTLE_SWITCH_NOTARY_PROFILE:-model-switch-notary}
if [ -z "$profile" ]; then
    release_error "LITTLE_SWITCH_NOTARY_PROFILE must not be empty"
fi

result=$(release_notary_result_path)
log=$(release_notary_log_path)
temporary_result=$result.tmp.$$
temporary_log=$log.tmp.$$

cleanup() {
    if [ -f "$temporary_result" ]; then
        /bin/rm -f "$temporary_result"
    fi
    if [ -f "$temporary_log" ]; then
        /bin/rm -f "$temporary_log"
    fi
}
trap cleanup EXIT HUP INT TERM

submit_status=0
"$xcrun" notarytool submit "$dmg" --keychain-profile "$profile" --wait --output-format json > "$temporary_result" \
    || submit_status=$?
/bin/mv -f "$temporary_result" "$result"
if [ "$submit_status" -ne 0 ]; then
    release_error "notarytool submission failed; result saved to $result"
fi

status=$("$plutil" -extract status raw -o - "$result") \
    || release_error "notarytool result does not contain a status"
submission_id=$("$plutil" -extract id raw -o - "$result") \
    || release_error "notarytool result does not contain a submission id"

"$xcrun" notarytool log "$submission_id" --keychain-profile "$profile" "$temporary_log"
/bin/mv -f "$temporary_log" "$log"

if [ "$status" != Accepted ]; then
    release_error "notarization status is $status; Apple log saved to $log"
fi

"$xcrun" stapler staple "$dmg"
"$xcrun" stapler validate "$dmg"

printf '%s\n' "$dmg"
