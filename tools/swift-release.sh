#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

# All release consumers use the same driver, scratch directory and flags.
# --show-bin-path queries this configuration without compiling it again.
exec xcrun swift build --disable-sandbox --build-system swiftbuild \
    --package-path "$project_root" \
    --scratch-path "$project_root/.build" \
    --configuration release --triple arm64-apple-macosx14.0 \
    --cache-path "$project_root/.build/cache" \
    --config-path "$project_root/.build/config" \
    --security-path "$project_root/.build/security" \
    -Xswiftc -warnings-as-errors \
    --product LittleSwitch "$@"
