#!/bin/sh
set -eu

script_root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=tools/release/common.sh
. "$script_root/common.sh"
release_initialize "$script_root/../.."

usage() {
    echo "usage: tools/release/publish-update.sh [--notes-file path] [--replace] [--push] " >&2
    exit 2
}

default_notes_file=$project_root/packaging/release-notes.md
notes_file=$default_notes_file
replace=0
push=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --push) push=1 ;;
        --replace) replace=1 ;;
        --notes-file)
            if [ "$#" -lt 2 ]; then
                usage
            fi
            notes_file=$2
            shift
            ;;
        *) usage ;;
    esac
    shift
done

homebrew_repository=${LITTLE_SWITCH_HOMEBREW_REPOSITORY:-$project_root/../homebrew-alfred}
sparkle_key=$HOME/.config/little-switch/sparkle-ed25519-private.key
if [ "${LITTLE_SWITCH_RELEASE_TESTING:-0}" = 1 ]; then
    sparkle_key=${LITTLE_SWITCH_RELEASE_SPARKLE_KEY:-$sparkle_key}
fi

# Primary: GitHub Releases in this repo. Appcast lives in packaging/.
releases_remote=alfred-labs/little-switch
