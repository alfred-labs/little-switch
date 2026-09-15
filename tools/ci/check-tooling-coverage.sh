#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_root"
coverage_scratch_path=.build/tooling-coverage

# Tooling coverage has its own build and profile, independent of application tests.
# Atomic increments also cover deterministic rules called by concurrent tests.
xcrun swift test --disable-sandbox --package-path tools --enable-code-coverage \
    --no-parallel \
    --scratch-path "$coverage_scratch_path" \
    --cache-path .build/tooling-cache --config-path .build/tooling-config --security-path .build/tooling-security \
    -Xswiftc -warnings-as-errors \
    -Xswiftc -Xllvm -Xswiftc -instrprof-atomic-counter-update-all

binary_path=$(xcrun swift build --show-bin-path --package-path tools \
    --scratch-path "$coverage_scratch_path" \
    --cache-path .build/tooling-cache --config-path .build/tooling-config --security-path .build/tooling-security)
profile="$binary_path/codecov/default.profdata"

coverage_test_binaries=$(find "$binary_path" -type f -perm -111 -path '*/Contents/MacOS/*Tests' | LC_ALL=C sort)
if [ -z "$coverage_test_binaries" ]; then
    echo "Tooling coverage test binaries were not produced" >&2
    exit 1
fi
if [ ! -f "$profile" ]; then
    echo "Tooling coverage instrumentation profile was not produced" >&2
    exit 1
fi

coverage_reports=$(mktemp -d "${TMPDIR:-/tmp}/little-switch-tooling-coverage-reports.XXXXXX")
trap 'rm -rf "$coverage_reports"' EXIT HUP INT TERM
measured_list="$coverage_reports/measured-sources.txt"
measured_report="$coverage_reports/measured-report.txt"
raw_report="$coverage_reports/raw-report.txt"

mise run --quiet tools:run -- coverage scope --root "$project_root/tools" \
    --manifest ci/tooling-coverage-exclusions.tsv --measured > "$measured_list"
if [ ! -s "$measured_list" ]; then
    echo "Coverage scope classifier returned no measured Swift sources" >&2
    exit 1
fi

set --
while IFS= read -r test_binary; do
    if [ ! -f "$test_binary" ]; then
        echo "Tooling coverage test binary disappeared: $test_binary" >&2
        exit 1
    fi
    # Only the first positional argument is a binary; the others are sources.
    if [ "$#" -eq 0 ]; then
        set -- "$test_binary"
    else
        set -- "$@" "-object=$test_binary"
    fi
done <<COVERAGE_TEST_BINARIES
$coverage_test_binaries
COVERAGE_TEST_BINARIES

while IFS= read -r source_path; do
    if [ -z "$source_path" ]; then
        echo "Coverage scope classifier returned an empty source path" >&2
        exit 1
    fi
    set -- "$@" "tools/$source_path"
done < "$measured_list"

xcrun llvm-cov report "$@" -instr-profile="$profile" > "$measured_report" 2>&1 || {
    status=$?
    cat "$measured_report" >&2
    echo "Failed to produce measured tooling source coverage report" >&2
    exit "$status"
}
printf '%s\n' "Measured tooling source coverage (100.00% lines required)"
cat "$measured_report"
mise run --quiet tools:run -- coverage verify --root "$project_root/tools" \
    --measured-list "$measured_list" --report "$measured_report"

set --
while IFS= read -r test_binary; do
    if [ "$#" -eq 0 ]; then
        set -- "$test_binary"
    else
        set -- "$@" "-object=$test_binary"
    fi
done <<COVERAGE_TEST_BINARIES
$coverage_test_binaries
COVERAGE_TEST_BINARIES
set -- "$@" "tools/Sources"
xcrun llvm-cov report "$@" -instr-profile="$profile" > "$raw_report" 2>&1 || {
    status=$?
    cat "$raw_report" >&2
    echo "Failed to produce raw linked-tooling-source coverage report" >&2
    exit "$status"
}
printf '\n%s\n' "Raw linked-tooling-source coverage (includes excluded adapters)"
cat "$raw_report"
mise run --quiet tools:run -- coverage verify --root "$project_root/tools" \
    --measured-list "$measured_list" --report "$measured_report" --raw-report "$raw_report"
