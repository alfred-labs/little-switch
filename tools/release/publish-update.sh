#!/bin/sh
set -eu

script_root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=tools/release/common.sh
. "$script_root/common.sh"
release_initialize "$script_root/../.."

usage() {
    echo "usage: tools/release/publish-update.sh [--notes-file path] [--replace] [--push]" >&2
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

# Everything publishes into the main repository: GitHub Releases carry the
# DMG, packaging/appcast.xml is the Sparkle feed clients fetch, and the
# Homebrew tap is updated last. The legacy little-switch-releases repository
# is archived and must not receive anything.
releases_remote=alfred-labs/little-switch
releases_repository=${LITTLE_SWITCH_RELEASES_REPOSITORY:-$project_root}
appcast=$releases_repository/packaging/appcast.xml

require_release_file "$bundle_info" "built application Info.plist"
require_release_file "$notes_file" "release notes"
version=$(release_version)
build=$("$plutil" -extract CFBundleVersion raw -o - "$bundle_info")
dmg=$(release_dmg_path)
require_release_file "$dmg" "notarized release image"
notary_result=$(release_notary_result_path)
require_release_file "$notary_result" "notarization result"
require_release_file "$sparkle_key" "Sparkle private key"
require_publication_repository "$releases_repository" "$releases_remote" Sparkle
sh "$script_root/publish-homebrew.sh" --check

tag="v$version"
signature=$(mise exec -- xcrun swift "$script_root/sparkle-sign.swift" "$sparkle_key" "$dmg")

echo "Publishing LittleSwitch $version (build $build) as $tag to $releases_remote"
gh release create "$tag" \
    --repo "$releases_remote" \
    --latest \
    --title "LittleSwitch $version" \
    --notes-file "$notes_file" \
    "$dmg#LittleSwitch-$version-arm64.dmg"

replace_arguments=()
if [ "$replace" = 1 ]; then
    replace_arguments=(--replace-version "$version")
fi

release_tools appcast \
    --version "$version" \
    --build "$build" \
    --dmg "$dmg" \
    --signature "$signature" \
    --notes-file "$notes_file" \
    "${replace_arguments[@]+"${replace_arguments[@]}"}" \
    --appcast "$appcast" \
    --output "$appcast"

if ! git -C "$releases_repository" diff --quiet -- packaging/appcast.xml; then
    git -C "$releases_repository" commit --only \
        -m "chore(release): LittleSwitch $version (build $build)" -- packaging/appcast.xml
fi

if [ "$push" = 1 ]; then
    git -C "$releases_repository" push origin main
    if ! sh "$script_root/publish-homebrew.sh" --push; then
        echo "Sparkle is published; retry Homebrew with: mise run release:homebrew -- --push" >&2
        exit 1
    fi
else
    sh "$script_root/publish-homebrew.sh"
    echo "Committed the Sparkle appcast and Homebrew cask. Push when ready:"
    echo "  git -C $releases_repository push origin main"
    echo "  git -C $homebrew_repository push origin main"
fi
