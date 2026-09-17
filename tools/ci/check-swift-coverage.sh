#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_root"
coverage_scratch_path=.build/coverage

# Async tests exercise shared functions concurrently even in a serial test run.
# Atomic profile increments prevent lost hits and inconsistent derived counts.
xcrun swift test --disable-sandbox --enable-code-coverage --disable-xctest \
    --toolset tools/ci/appkit-coverage-test-runner.json \
    --no-parallel \
    --scratch-path "$coverage_scratch_path" \
    --cache-path .build/cache --config-path .build/config --security-path .build/security \
    -Xswiftc -warnings-as-errors \
    -Xswiftc -Xllvm -Xswiftc -instrprof-atomic-counter-update-all

binary_path=$(xcrun swift build --show-bin-path \
    --scratch-path "$coverage_scratch_path" \
    --cache-path .build/cache --config-path .build/config --security-path .build/security)
profile="$binary_path/codecov/default.profdata"

coverage_test_binaries=$(find "$binary_path" -type f -perm -111 -path '*/Contents/MacOS/*Tests' | LC_ALL=C sort)
if [ -z "$coverage_test_binaries" ]; then
    echo "Coverage test binaries were not produced" >&2
    exit 1
fi
if [ ! -f "$profile" ]; then
    echo "Coverage instrumentation profile was not produced" >&2
    exit 1
fi

coverage_reports=$(mktemp -d "${TMPDIR:-/tmp}/little-switch-coverage-reports.XXXXXX")
trap 'rm -rf "$coverage_reports"' EXIT HUP INT TERM
measured_list="$coverage_reports/measured-sources.txt"
measured_report="$coverage_reports/measured-report.txt"
raw_report="$coverage_reports/raw-report.txt"

mise run --quiet tools:run -- coverage scope --measured > "$measured_list"
if [ ! -s "$measured_list" ]; then
    echo "Coverage scope classifier returned no measured Swift sources" >&2
    exit 1
fi

set --
while IFS= read -r test_binary; do
    if [ ! -f "$test_binary" ]; then
        echo "Coverage test binary disappeared: $test_binary" >&2
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
    set -- "$@" "$source_path"
done < "$measured_list"

xcrun llvm-cov report "$@" -instr-profile="$profile" > "$measured_report" 2>&1 || {
    status=$?
    cat "$measured_report" >&2
    echo "Failed to produce measured source coverage report" >&2
    exit "$status"
}

printf '%s\n' "Measured source coverage (100.00% lines required)"
cat "$measured_report"
mise run --quiet tools:run -- coverage verify --measured-list "$measured_list" --report "$measured_report"

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
set -- "$@" "Sources"
xcrun llvm-cov report "$@" -instr-profile="$profile" > "$raw_report" 2>&1 || {
    status=$?
    cat "$raw_report" >&2
    echo "Failed to produce raw linked-source coverage report" >&2
    exit "$status"
}

printf '\n%s\n' "Raw linked-source coverage (includes excluded adapters)"
cat "$raw_report"
mise run --quiet tools:run -- coverage verify \
    --measured-list "$measured_list" --report "$measured_report" --raw-report "$raw_report"
