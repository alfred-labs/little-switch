import Foundation

struct AppBuildFixture {
    let root: URL
    let environment: [String: String]

    var productDirectory: String { ".build/out/Products/Release" }
    var bundleDirectory: String { "build/LittleSwitch.app/Contents" }

    init(root: URL) throws {
        self.root = root
        environment = [
            "PATH": root.appendingPathComponent("bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin",
            "FAKE_ROOT": root.path,
        ]
        for script in ["tools/build-app.sh", "tools/swift-release.sh", "tools/ci/verify-bundle.sh"] {
            let source = try RepositoryFixture.root().appendingPathComponent(script)
            if FileManager.default.fileExists(atPath: source.path) {
                try write(script, String(contentsOf: source, encoding: .utf8), executable: true)
            }
        }
        try write("bin/xcrun", Self.xcrun, executable: true)
        try write("tools/generate-app-icon.sh", "#!/bin/sh\nprintf icon > \"$1\"\n", executable: true)
        try write("tools/ci/verify-app-icon.sh", "#!/bin/sh\nexit 0\n", executable: true)
        try write("tools/resolve-signing-identity.sh", "#!/bin/sh\nexit 0\n", executable: true)
        try write("packaging/version.env", "MARKETING_VERSION=1.2.3\nBUILD_NUMBER=12\n")
        try write("packaging/Info.plist", RepositoryFixture.text("packaging/Info.plist"))
        for path in [
            "LICENSE", "THIRD_PARTY_NOTICES.md", "Vendor/OrderedJSON/LICENSE",
            "schemas/upstream/notices/anthropic.LICENSE", "schemas/upstream/notices/openai.LICENSE",
        ] {
            try write(path, "fixture license\n")
        }
        for dependency in ["hummingbird", "async-http-client", "swift-nio"] {
            try write(".build/checkouts/\(dependency)/LICENSE.txt", "fixture license\n")
        }
        try write(
            ".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/fixture",
            "sparkle")
        try write("\(productDirectory)/LittleSwitch", "current executable\n", executable: true)
        try write(".build/arm64-apple-macosx/release/LittleSwitch", "stale executable\n", executable: true)
        for target in ["LittleSwitchCore", "LittleSwitchUI"] {
            try write(
                "\(productDirectory)/LittleSwitch_\(target).bundle/Contents/Resources/fr.lproj/Localizable.strings",
                "\"Overview\" = \"Aperçu\";\n")
        }
        try write("\(bundleDirectory)/previous-bundle", "preserved on failure\n")
        try write("calls", "")
    }

    func write(_ path: String, _ contents: String, executable: Bool = false) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: file)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
    }

    func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func run(
        _ script: String = "tools/build-app.sh",
        arguments: [String] = [],
        overrides: [String: String] = [:]
    ) throws -> RepositoryProcess.Result {
        try RepositoryProcess.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: [root.appendingPathComponent(script).path] + arguments,
            directory: root,
            environment: environment.merging(overrides) { _, new in new })
    }

    private static let xcrun = #"""
        #!/bin/sh
        set -eu
        printf '%s' "$1" >> "$FAKE_ROOT/calls"
        for argument in "$@"; do printf '\t%s' "$argument" >> "$FAKE_ROOT/calls"; done
        printf '\n' >> "$FAKE_ROOT/calls"
        case "$1" in
            swift)
                for argument in "$@"; do
                    if [ "$argument" = --show-bin-path ]; then
                        if [ "${FAKE_PATH_STATUS:-0}" != 0 ]; then
                            echo 'path lookup failed' >&2
                            exit "$FAKE_PATH_STATUS"
                        fi
                        printf '%s\n' "$FAKE_ROOT/.build/out/Products/Release"
                        exit 0
                    fi
                done
                if [ "${FAKE_BUILD_STATUS:-0}" != 0 ]; then echo 'compilation failed' >&2; fi
                exit "${FAKE_BUILD_STATUS:-0}"
                ;;
            otool) echo 'path @executable_path/../Frameworks' ;;
            swift-stdlib-tool)
                shift
                action=$1
                destination=
                while [ "$#" -gt 0 ]; do
                    if [ "$1" = --destination ]; then shift; destination=$1; fi
                    shift
                done
                case "$action" in
                    --print) printf '%s\n' '/fixture/toolchain/libswiftCompatibilitySpan.dylib' ;;
                    --copy) printf 'swift compatibility runtime\n' > "$destination/libswiftCompatibilitySpan.dylib" ;;
                    *) exit 90 ;;
                esac
                ;;
            lipo) echo arm64 ;;
            dwarfdump)
                case "$(cat "$3")" in
                    'current executable') uuid=11111111-1111-1111-1111-111111111111 ;;
                    *) uuid=22222222-2222-2222-2222-222222222222 ;;
                esac
                printf 'UUID: %s (arm64) %s\n' "$uuid" "$3"
                ;;
            *) echo "unexpected Apple tool: $1" >&2; exit 90 ;;
        esac
        """#
}
