#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 /absolute/path/to/AppIcon.icns" >&2
    exit 64
fi

icon=$1
test -f "$icon"

validation_root=$(mktemp -d "${TMPDIR:-/tmp}/little-switch-app-icon-validation.XXXXXX")
trap 'rm -rf "$validation_root"' EXIT HUP INT TERM
iconset="$validation_root/AppIcon.iconset"

/usr/bin/iconutil -c iconset "$icon" -o "$iconset"

check_representation() {
    filename=$1
    pixels=$2
    path="$iconset/$filename"
    test -f "$path"
    width=$(/usr/bin/sips -g pixelWidth "$path" | /usr/bin/awk '/pixelWidth:/{print $2}')
    height=$(/usr/bin/sips -g pixelHeight "$path" | /usr/bin/awk '/pixelHeight:/{print $2}')
    test "$width" = "$pixels"
    test "$height" = "$pixels"
}

check_representation icon_16x16.png 16
check_representation icon_16x16@2x.png 32
check_representation icon_32x32.png 32
check_representation icon_32x32@2x.png 64
check_representation icon_128x128.png 128
check_representation icon_128x128@2x.png 256
check_representation icon_256x256.png 256
check_representation icon_256x256@2x.png 512
check_representation icon_512x512.png 512
check_representation icon_512x512@2x.png 1024

echo "Verified $icon"
