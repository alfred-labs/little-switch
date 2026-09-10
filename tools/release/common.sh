#!/bin/sh

release_error() {
    printf 'LittleSwitch release: %s\n' "$*" >&2
    return 1
}

release_initialize() {
    source_root=$1
    detected_project_root=$(CDPATH= cd -- "$source_root" && pwd)

    if [ "${LITTLE_SWITCH_RELEASE_TESTING:-0}" = 1 ]; then
        project_root=${LITTLE_SWITCH_RELEASE_PROJECT_ROOT:-$detected_project_root}
        codesign=${LITTLE_SWITCH_RELEASE_CODESIGN:-/usr/bin/codesign}
        ditto=${LITTLE_SWITCH_RELEASE_DITTO:-/usr/bin/ditto}
        hdiutil=${LITTLE_SWITCH_RELEASE_HDIUTIL:-/usr/bin/hdiutil}
        lipo=${LITTLE_SWITCH_RELEASE_LIPO:-/usr/bin/lipo}
        plutil=${LITTLE_SWITCH_RELEASE_PLUTIL:-/usr/bin/plutil}
        spctl=${LITTLE_SWITCH_RELEASE_SPCTL:-/usr/sbin/spctl}
        xcrun=${LITTLE_SWITCH_RELEASE_XCRUN:-/usr/bin/xcrun}
        app_builder=${LITTLE_SWITCH_RELEASE_APP_BUILDER:-$project_root/tools/build-app.sh}
        bundle_verifier=${LITTLE_SWITCH_RELEASE_BUNDLE_VERIFIER:-$project_root/tools/ci/verify-bundle.sh}
        identity_resolver=${LITTLE_SWITCH_RELEASE_IDENTITY_RESOLVER:-$project_root/tools/resolve-signing-identity.sh}
    else
        project_root=$detected_project_root
        codesign=/usr/bin/codesign
        ditto=/usr/bin/ditto
        hdiutil=/usr/bin/hdiutil
        lipo=/usr/bin/lipo
        plutil=/usr/bin/plutil
        spctl=/usr/sbin/spctl
        xcrun=/usr/bin/xcrun
        app_builder=$project_root/tools/build-app.sh
        bundle_verifier=$project_root/tools/ci/verify-bundle.sh
        identity_resolver=$project_root/tools/resolve-signing-identity.sh
    fi

    bundle=$project_root/build/LittleSwitch.app
    bundle_info=$bundle/Contents/Info.plist
    bundle_executable=$bundle/Contents/MacOS/LittleSwitch
    dist_directory=$project_root/dist
    signing_env=$project_root/.signing.env
    if [ ! -f "$signing_env" ]; then
        signing_env=$project_root/.env
    fi
}

resolve_release_identity() {
    "$identity_resolver" "$signing_env"
}

release_tools() {
    mise run --quiet tools:run -- release --root "$project_root" "$@"
}

require_developer_id_application() {
    identity=$1
    case "$identity" in
        'Developer ID Application:'*) return 0 ;;
        '') release_error "a Developer ID Application signing identity is required" ;;
        *) release_error "signing identity must begin with 'Developer ID Application:'" ;;
    esac
}

require_release_file() {
    path=$1
    label=$2
    if [ ! -e "$path" ]; then
        release_error "$label not found at $path"
    fi
}

require_publication_repository() {
    publication_repository=$1
    publication_remote=$2
    publication_label=$3
    require_release_file "$publication_repository" "$publication_label repository"
    publication_root=$(CDPATH= cd -- "$publication_repository" && pwd -P)
    publication_git_root=$(git -C "$publication_repository" rev-parse --show-toplevel)
    if [ "$publication_root" != "$publication_git_root" ]; then
        release_error "$publication_label path must be the root of its Git repository"
        return 1
    fi
    case "$(git -C "$publication_repository" remote get-url origin)" in
        "git@github.com:$publication_remote.git"|"https://github.com/$publication_remote.git"|"https://github.com/$publication_remote") ;;
        *) release_error "$publication_label origin must point to $publication_remote"; return 1 ;;
    esac
    publication_push_urls=$(git -C "$publication_repository" remote get-url --push --all origin)
    while IFS= read -r publication_push_url; do
        case "$publication_push_url" in
            "git@github.com:$publication_remote.git"|"https://github.com/$publication_remote.git"|"https://github.com/$publication_remote") ;;
            *) release_error "$publication_label push URLs must point to $publication_remote"; return 1 ;;
        esac
    done <<EOF
$publication_push_urls
EOF
    if [ "$(git -C "$publication_repository" symbolic-ref --short HEAD)" != main ]; then
        release_error "$publication_label repository must be on main"
        return 1
    fi
    publication_status=$(git -C "$publication_repository" status --porcelain --untracked-files=normal)
    if [ -n "$publication_status" ]; then
        release_error "$publication_label repository must be clean; preserve or commit its uncommitted changes first"
        return 1
    fi
}

release_version() {
    require_release_file "$bundle_info" "built application Info.plist"
    "$plutil" -extract CFBundleShortVersionString raw -o - "$bundle_info"
}

release_dmg_path() {
    version=$(release_version)
    printf '%s/LittleSwitch-%s-arm64.dmg\n' "$dist_directory" "$version"
}

release_notary_result_path() {
    dmg=$(release_dmg_path)
    printf '%s.notary-result.json\n' "${dmg%.dmg}"
}

release_notary_log_path() {
    dmg=$(release_dmg_path)
    printf '%s.notary-log.json\n' "${dmg%.dmg}"
}

require_signature_metadata() {
    signed_item=$1
    expected_identifier=$2
    signature=$3

    printf '%s\n' "$signature" | /usr/bin/grep -F "Authority=Developer ID Application:" >/dev/null \
        || release_error "$signed_item is not signed with Developer ID Application"
    printf '%s\n' "$signature" | /usr/bin/grep -F 'Timestamp=' >/dev/null \
        || release_error "$signed_item has no secure timestamp"
    printf '%s\n' "$signature" | /usr/bin/grep -F "Identifier=$expected_identifier" >/dev/null \
        || release_error "$signed_item has an unexpected signing identifier"
}
