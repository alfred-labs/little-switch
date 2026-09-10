#!/bin/sh
set -eu

script_root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=tools/release/common.sh
. "$script_root/common.sh"
release_initialize "$script_root/../.."

check=0
push=0
for argument in "$@"; do
    case "$argument" in
        --check) check=1 ;;
        --push) push=1 ;;
        *) echo "usage: publish-homebrew.sh [--check | --push]" >&2; exit 2 ;;
    esac
done
if [ "$check" = 1 ] && [ "$push" = 1 ]; then
    release_error "--check and --push are mutually exclusive"
    exit 2
fi

homebrew_repository=${LITTLE_SWITCH_HOMEBREW_REPOSITORY:-$project_root/../homebrew-alfred}
require_publication_repository "$homebrew_repository" alfred-labs/homebrew-alfred Homebrew
cask=$homebrew_repository/Casks/littleswitch.rb
require_release_file "$cask" "LittleSwitch Homebrew cask"
version=$(release_version)
dmg=$(release_dmg_path)
require_release_file "$dmg" "notarized release DMG"

release_tools homebrew \
    --version "$version" --dmg "$dmg" --cask "$cask" --check
if [ "$check" = 1 ]; then
    exit 0
fi

metadata=$(mktemp "${TMPDIR:-/tmp}/little-switch-homebrew-metadata.XXXXXX")
trap 'rm -f "$metadata"' EXIT
gh api "repos/alfred-labs/little-switch/releases/tags/v$version" \
    --jq '{tag_name, draft, prerelease, assets: [.assets[] | {name, digest, size, browser_download_url}]}' \
    > "$metadata"
# Recheck after the network request so concurrent local edits are preserved.
require_publication_repository "$homebrew_repository" alfred-labs/homebrew-alfred Homebrew
release_tools homebrew \
    --version "$version" --dmg "$dmg" --cask "$cask" --release-metadata "$metadata"

if ! git -C "$homebrew_repository" diff --quiet -- Casks/littleswitch.rb; then
    git -C "$homebrew_repository" commit --only \
        -m "release: LittleSwitch $version" -- Casks/littleswitch.rb
fi
if [ "$push" = 1 ]; then
    git -C "$homebrew_repository" push origin main
fi
printf 'Homebrew cask ready for LittleSwitch %s in %s\n' "$version" "$homebrew_repository"
