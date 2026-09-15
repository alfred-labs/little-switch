import Foundation

struct CoverageGateFixture {
    enum Package: String, CaseIterable {
        case app
        case tooling

        var script: String { self == .app ? "check-swift-coverage.sh" : "check-tooling-coverage.sh" }
        var testProduct: String { "CoverageTests" }
    }

    var sources = ["Sources/App/A.swift"]
    var exclusions = ""
    var measuredReport = CoverageFixture.report()
    var rawReport = CoverageFixture.report()
    var measuredWarning = ""
    var rawWarning = ""
    var measuredStatus = 0
    var rawStatus = 0
    var testStatus = 0
    var missingArtifact = ""
    var additionalTestProducts: [String] = []

    func run(package: Package = .app) throws -> (result: RepositoryProcess.Result, invocations: String) {
        try withTemporaryDirectory { root in
            let scopeRoot = package == .app ? root : root.appendingPathComponent("tools", isDirectory: true)
            let manifest = package == .app ? CoverageFixture.manifest : "ci/tooling-coverage-exclusions.tsv"
            try CoverageFixture.write(at: scopeRoot, sources: sources, exclusions: exclusions, manifest: manifest)
            let scriptURL = root.appendingPathComponent("tools/ci/" + package.script)
            try FileManager.default.createDirectory(
                at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(RepositoryFixture.text("tools/ci/" + package.script).utf8).write(to: scriptURL)
            let bin = root.appendingPathComponent("current-coverage-bin", isDirectory: true)
            let testProduct = package.testProduct
            let binary = bin.appendingPathComponent("\(testProduct).xctest/Contents/MacOS/\(testProduct)")
            let binaries = ([testProduct] + additionalTestProducts).sorted().map {
                bin.appendingPathComponent("\($0).xctest/Contents/MacOS/\($0)")
            }
            let profile = bin.appendingPathComponent("codecov/default.profdata")
            for artifact in binaries + [profile] where artifact.lastPathComponent != missingArtifact {
                try FileManager.default.createDirectory(
                    at: artifact.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("current fixture".utf8).write(to: artifact)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: artifact.path)
            }
            let stale = root.appendingPathComponent(".build/arm64-apple-macosx/debug", isDirectory: true)
            for path in ["\(testProduct).xctest/Contents/MacOS/\(testProduct)", "codecov/default.profdata"] {
                let artifact = stale.appendingPathComponent(path)
                try FileManager.default.createDirectory(
                    at: artifact.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("stale fixture".utf8).write(to: artifact)
            }
            let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
            try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
            for (name, contents) in [("xcrun", Self.xcrun), ("mise", Self.mise)] {
                let file = fakeBin.appendingPathComponent(name)
                try Data(contents.utf8).write(to: file)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            }
            let measured = root.appendingPathComponent("measured-report.txt")
            let raw = root.appendingPathComponent("raw-report.txt")
            try Data(measuredReport.utf8).write(to: measured)
            try Data(rawReport.utf8).write(to: raw)
            let log = root.appendingPathComponent("invocations.txt")
            let expectedObjects = root.appendingPathComponent("expected-objects.txt")
            try Data((binaries.map(\.path).joined(separator: "\n") + "\n").utf8).write(to: expectedObjects)
            var environment = ProcessInfo.processInfo.environment
            environment.merge([
                "PATH": fakeBin.path + ":" + environment["PATH", default: ""],
                "FAKE_ROOT": root.path, "FAKE_CLI": try RepositoryProcess.toolingExecutable().path,
                "FAKE_LOG": log.path, "FAKE_BIN": bin.path, "FAKE_BINARY": binary.path, "FAKE_PROFILE": profile.path,
                "FAKE_MEASURED": measured.path, "FAKE_RAW": raw.path,
                "FAKE_MEASURED_WARNING": measuredWarning, "FAKE_RAW_WARNING": rawWarning,
                "FAKE_MEASURED_STATUS": String(measuredStatus), "FAKE_RAW_STATUS": String(rawStatus),
                "FAKE_TEST_STATUS": String(testStatus),
                "FAKE_OBJECTS": expectedObjects.path,
                "FAKE_ACTUAL_OBJECTS": root.appendingPathComponent("actual-objects.txt").path,
            ]) { _, new in new }
            let result = try RepositoryProcess.run(
                URL(fileURLWithPath: "/bin/sh"),
                arguments: [scriptURL.path],
                directory: root,
                environment: environment)
            return try (result, String(contentsOf: log, encoding: .utf8))
        }
    }

    private static let mise = #"""
        #!/bin/sh
        set -eu
        while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done
        shift
        exec "$FAKE_CLI" --root "$FAKE_ROOT" "$@"
        """#

    private static let xcrun = #"""
        #!/bin/sh
        set -eu
        printf '%s' "$1" >> "$FAKE_LOG"
        for argument in "$@"; do printf '\t%s' "$argument" >> "$FAKE_LOG"; done
        printf '\n' >> "$FAKE_LOG"
        if [ "$1" = "swift" ] && [ "$2" = "build" ]; then
            printf '%s\n' "$FAKE_BIN"
            exit 0
        fi
        if [ "$1" = "swift" ]; then exit "$FAKE_TEST_STATUS"; fi
        if [ "$1" != "llvm-cov" ] || [ "$2" != "report" ]; then exit 2; fi
        printf '%s\n' "$3" > "$FAKE_ACTUAL_OBJECTS"
        profile_seen=
        for argument in "$@"; do
            case "$argument" in
                -instr-profile=*)
                    [ "$argument" = "-instr-profile=$FAKE_PROFILE" ] || exit 3
                    profile_seen=1 ;;
                -object=*) printf '%s\n' "${argument#-object=}" >> "$FAKE_ACTUAL_OBJECTS" ;;
            esac
        done
        [ -n "$profile_seen" ] || exit 3
        if ! cmp -s "$FAKE_OBJECTS" "$FAKE_ACTUAL_OBJECTS"; then
            echo 'coverage gate omitted a test bundle from the coverage objects' >&2
            exit 3
        fi
        if [ "$3" != "$FAKE_BINARY" ]; then
            echo 'coverage gate selected stale or mismatched artifacts' >&2
            exit 3
        fi
        raw_report=
        for argument in "$@"; do
            if [ "$argument" = "Sources" ] || [ "$argument" = "tools/Sources" ]; then
                raw_report=1
            fi
        done
        if [ -n "$raw_report" ]; then
            cat "$FAKE_RAW"
            if [ -n "$FAKE_RAW_WARNING" ]; then printf '%s\n' "$FAKE_RAW_WARNING" >&2; fi
            exit "$FAKE_RAW_STATUS"
        fi
        cat "$FAKE_MEASURED"
        if [ -n "$FAKE_MEASURED_WARNING" ]; then printf '%s\n' "$FAKE_MEASURED_WARNING" >&2; fi
        exit "$FAKE_MEASURED_STATUS"
        """#
}
