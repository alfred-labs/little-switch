#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 /absolute/path/to/AppIcon.icns" >&2
    exit 64
fi

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_icon="$project_root/packaging/AppIcon.svg"
destination=$1
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/little-switch-app-icon.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM
iconset="$temporary_root/AppIcon.iconset"
thumbnail_directory="$temporary_root/thumbnail"
master_icon="$thumbnail_directory/AppIcon.svg.png"

mkdir -p "$iconset" "$thumbnail_directory" "$(dirname -- "$destination")"

/usr/bin/qlmanage -t -s 1024 -o "$thumbnail_directory" "$source_icon" >/dev/null
test -f "$master_icon"

render() {
    filename=$1
    pixels=$2
    /usr/bin/sips -s format png --resampleHeightWidth "$pixels" "$pixels" \
        "$master_icon" --out "$iconset/$filename" >/dev/null
}

render icon_16x16.png 16
render icon_16x16@2x.png 32
render icon_32x32.png 32
render icon_32x32@2x.png 64
render icon_128x128.png 128
render icon_128x128@2x.png 256
render icon_256x256.png 256
render icon_256x256@2x.png 512
render icon_512x512.png 512
cp "$master_icon" "$iconset/icon_512x512@2x.png"

/usr/bin/iconutil -c icns "$iconset" -o "$destination"
