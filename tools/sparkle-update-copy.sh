#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: sparkle-update-copy.sh <apply|verify> <Sparkle.framework>" >&2
    exit 1
fi
mode=$1
framework=$2
case "$mode" in
    apply|verify) ;;
    *) echo "Unknown Sparkle update copy mode: $mode" >&2; exit 1 ;;
esac

# Customize only the bundled resources, before code signing. Never modify the
# SwiftPM artifact or replace Sparkle's UI/installation logic. Base is English.
key='%@ %@ is now available—you have %@. Would you like to download it now?'
for language in Base fr; do
    strings="$framework/Resources/$language.lproj/Sparkle.strings"
    if [ ! -f "$strings" ] || ! /usr/libexec/PlistBuddy -c "Print :'$key'" "$strings" >/dev/null 2>&1; then
        echo "Sparkle update summary key missing in $strings; review upstream copy before bundling." >&2
        exit 1
    fi
done

for language in Base fr; do
    strings="$framework/Resources/$language.lproj/Sparkle.strings"
    case "$language" in
        Base) summary='%1$@ %2$@ is now available.' ;;
        fr) summary='%1$@ %2$@ est disponible.' ;;
    esac
    if [ "$mode" = apply ]; then
        /usr/libexec/PlistBuddy -c "Set :'$key' $summary" "$strings"
    elif [ "$(/usr/libexec/PlistBuddy -c "Print :'$key'" "$strings")" != "$summary" ]; then
        echo "Unexpected Sparkle update summary in $strings" >&2
        exit 1
    fi
done
