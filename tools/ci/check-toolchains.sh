#!/bin/sh
set -eu

test "$(uname -m)" = "arm64"

xcode_version="$(xcrun xcodebuild -version | sed -n '1s/^Xcode //p')"
swift_version="$(xcrun swift --version | sed -n '1s/.*Swift version \([0-9.]*\).*/\1/p')"
format_path="$(xcrun --find swift-format)"
lint_version="$(swiftlint version)"

test "$xcode_version" = "27.0"
test "$swift_version" = "6.4"
test -x "$format_path"
test "$lint_version" = "0.65.0"

echo "Xcode $xcode_version, Swift $swift_version, SwiftLint $lint_version, arm64"
