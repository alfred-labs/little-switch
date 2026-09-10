#!/bin/sh
set -eu

script_root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=tools/release/common.sh
. "$script_root/common.sh"
release_initialize "$script_root/../.."

usage() {
    echo "usage: tools/release/publish-update.sh [--notes-file path] [--replace] [--push] [--legacy-appcast]" >&2
    exit 2
}

default_notes_file=$project_root/packaging/release-notes.md
notes_file=$default_notes_file
replace=0
push=0
legacy_appcast=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --push) push=1 ;;
        --replace) replace=1 ;;
        --legacy-appcast) legacy_appcast=1 ;;
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

# Legacy appcast for the 3-week transition window. Existing installs with the
# old SUFeedURL continue to receive updates until they pick up the new URL.
legacy_repository=${LITTLE_SWITCH_LEGACY_RELEASES_REPOSITORY:-$project_root/../little-switch-releases}
legacy_remote=alfred-labs/little-switch-releases

require_release_file "$bundle_info" "built application Info.plist"
require_release_file "$notes_file" "release notes"
version=$(release_version)
build=$("$plutil" -extract CFBundleVersion raw -o - "$bundle_info")
dmg=$(release_dmg_path)
require_release_file "$dmg" "notarized release image"
notary_result=$(release_notary_result_path)
require_release_file "$notary_result" "notarization result"
require_release_file "$sparkle_key" "Sparkle private key"
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
    --appcast "$project_root/packaging/appcast.xml" \
    --output "$project_root/packaging/appcast.xml"

git commit --only \
    -m "release: LittleSwitch $version (build $build)" -- packaging/appcast.xml

# During the transition window, mirror the release to the legacy appcast so
# installs with the old SUFeedURL still receive updates.
if [ "$legacy_appcast" = 1 ]; then
    require_publication_repository "$legacy_repository" "$legacy_remote" Legacy
    echo "Mirroring release to legacy appcast ($legacy_remote)"
    release_tools appcast \
        --version "$version" \
        --build "$build" \
        --dmg "$dmg" \
        --signature "$signature" \
        --notes-file "$notes_file" \
        "${replace_arguments[@]+"${replace_arguments[@]}"}" \
        --appcast "$legacy_repository/appcast.xml" \
        --output "$legacy_repository/appcast.xml"
    git -C "$legacy_repository" commit --only \
        -m "release: LittleSwitch $version (build $build)" -- appcast.xml
fi

if [ "$push" = 1 ]; then
    git push origin main
    if [ "$legacy_appcast" = 1 ]; then
        git -C "$legacy_repository" push origin main
    fi
    if ! sh "$script_root/publish-homebrew.sh" --push; then
        echo "Sparkle is published; retry Homebrew with: mise run release:homebrew -- --push" >&2
        exit 1
    fi
else
    sh "$script_root/publish-homebrew.sh"
    echo "Committed the Sparkle appcast and Homebrew cask. Push when ready:"
    echo "  git push origin main"
    if [ "$legacy_appcast" = 1 ]; then
        echo "  git -C $legacy_repository push origin main"
    fi
    echo "  git -C $homebrew_repository push origin main"
fi
