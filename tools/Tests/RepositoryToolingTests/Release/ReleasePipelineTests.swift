import Foundation
import Testing

@Suite("Release Apple pipeline")
struct ReleasePipelineTests {
    @Test("Non-Developer-ID identities are refused before building")
    func rejectsDevelopmentIdentity() throws {
        try withTemporaryDirectory { root in
            let fixture = try ReleaseFixture(root: root)
            try fixture.tool("identity", "echo 'Apple Development: Example (TEAMID1234)'")
            try fixture.tool("builder", "touch \"$FAKE_ROOT/builder-ran\"")
            let result = try fixture.run(
                "create-dmg.sh",
                overrides: [
                    "LITTLE_SWITCH_RELEASE_IDENTITY_RESOLVER": root.appendingPathComponent("bin/identity").path,
                    "LITTLE_SWITCH_RELEASE_APP_BUILDER": root.appendingPathComponent("bin/builder").path,
                ])
            #expect(result.status != 0)
            #expect(result.stderr.contains("Developer ID Application"))
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("builder-ran").path))
        }
    }

    @Test("DMG creation builds, verifies, packages and signs in order")
    func createsSignedDMG() throws {
        try withTemporaryDirectory { root in
            let fixture = try ReleaseFixture(root: root)
            try fixture.tool("identity", "echo 'Developer ID Application: Example (TEAMID1234)'")
            try fixture.tool(
                "builder",
                #"""
                printf 'builder %s\n' "$LITTLE_SWITCH_SIGN_IDENTITY" >> "$FAKE_ROOT/calls"
                mkdir -p "$FAKE_ROOT/build/LittleSwitch.app/Contents/MacOS"
                touch "$FAKE_ROOT/build/LittleSwitch.app/Contents/MacOS/LittleSwitch"
                """#)
            try fixture.tool("verify-bundle", "echo verify-bundle >> \"$FAKE_ROOT/calls\"")
            try fixture.tool("codesign", "printf 'codesign %s\\n' \"$*\" >> \"$FAKE_ROOT/calls\"")
            try fixture.tool("ditto", "echo ditto >> \"$FAKE_ROOT/calls\"\n/bin/cp -R \"$1\" \"$2\"")
            try fixture.tool(
                "hdiutil",
                #"""
                printf 'hdiutil %s\n' "$*" >> "$FAKE_ROOT/calls"
                for argument in "$@"; do output=$argument; done
                printf '%s' 'signed fixture' > "$output"
                """#)
            var overrides = ["TMPDIR": root.path + "/"]
            for (variable, name) in [
                ("IDENTITY_RESOLVER", "identity"), ("APP_BUILDER", "builder"), ("BUNDLE_VERIFIER", "verify-bundle"),
                ("CODESIGN", "codesign"), ("DITTO", "ditto"), ("HDIUTIL", "hdiutil"),
            ] { overrides["LITTLE_SWITCH_RELEASE_" + variable] = root.appendingPathComponent("bin/" + name).path }
            let result = try fixture.run("create-dmg.sh", overrides: overrides)
            #expect(result.status == 0, "\(result.stderr)")
            #expect(try fixture.read("dist/LittleSwitch-1.2.3-arm64.dmg") == "signed fixture")
            let calls = try fixture.read("calls").split(separator: "\n")
            #expect(calls.count == 7)
            #expect(calls[0] == "builder Developer ID Application: Example (TEAMID1234)")
            #expect(calls[1] == "verify-bundle")
            #expect(calls[2].hasPrefix("codesign --verify --deep --strict"))
            #expect(calls[3] == "ditto")
            #expect(calls[4].hasPrefix("hdiutil create -srcfolder"))
            #expect(calls[4].contains("-format UDZO"))
            #expect(calls[5].hasPrefix("codesign --force --timestamp"))
            #expect(calls[5].contains("--identifier com.alfredlabs.littleswitch.dmg"))
            #expect(calls[6].hasPrefix("codesign --verify --strict"))
        }
    }

    @Test(
        "Notarization retains results and logs and staples only Accepted submissions",
        arguments: ["Accepted", "Invalid", "submit-failed"])
    func notarization(status: String) throws {
        try withTemporaryDirectory { root in
            let fixture = try ReleaseFixture(root: root)
            try fixture.tool(
                "plutil",
                #"""
                case "$2" in
                    CFBundleShortVersionString) echo 1.2.3 ;;
                    status) printf '%s\n' "$FAKE_NOTARY_STATUS" ;;
                    id) echo submission-id ;;
                esac
                """#)
            try fixture.tool(
                "xcrun",
                #"""
                printf '%s\n' "$*" >> "$FAKE_ROOT/calls"
                if [ "$1 $2" = 'notarytool submit' ]; then
                    printf '{"id":"submission-id","status":"%s"}\n' "$FAKE_NOTARY_STATUS"
                    [ "$FAKE_NOTARY_STATUS" != submit-failed ] || exit 8
                elif [ "$1 $2" = 'notarytool log' ]; then
                    for argument in "$@"; do output=$argument; done
                    printf '%s\n' '{"issues":[{"message":"fixture result"}]}' > "$output"
                fi
                """#)
            let result = try fixture.run(
                "notarize-dmg.sh",
                overrides: [
                    "LITTLE_SWITCH_RELEASE_XCRUN": root.appendingPathComponent("bin/xcrun").path,
                    "FAKE_NOTARY_STATUS": status,
                ])
            #expect((result.status == 0) == (status == "Accepted"))
            #expect(try fixture.read("dist/LittleSwitch-1.2.3-arm64.notary-result.json").contains(status))
            let calls = try fixture.read("calls")
            #expect(calls.contains("--keychain-profile model-switch-notary --wait --output-format json"))
            #expect(!calls.contains("--password"))
            #expect(!calls.contains("--apple-id"))
            if status == "submit-failed" {
                #expect(result.stderr.contains("submission failed"))
                #expect(!calls.contains("notarytool log"))
            } else {
                #expect(try fixture.read("dist/LittleSwitch-1.2.3-arm64.notary-log.json").contains("fixture result"))
                if status == "Invalid" { #expect(result.stderr.contains("status is Invalid")) }
            }
            #expect(calls.contains("stapler staple") == (status == "Accepted"))
            #expect(calls.contains("stapler validate") == (status == "Accepted"))
        }
    }

    @Test("The delivered app is mounted read-only, assessed and detached")
    func deliveredArtifact() throws {
        try withTemporaryDirectory { root in
            let fixture = try ReleaseFixture(root: root)
            try fixture.tool(
                "hdiutil",
                #"""
                printf 'hdiutil %s\n' "$*" >> "$FAKE_ROOT/calls"
                case "$1" in
                    attach)
                        [ "$2 $3 $4" = '-readonly -nobrowse -mountpoint' ] || exit 2
                        mkdir -p "$5/LittleSwitch.app/Contents/MacOS"
                        touch "$5/LittleSwitch.app/Contents/MacOS/LittleSwitch"
                        ;;
                    detach) /bin/rm -rf "$2/LittleSwitch.app" ;;
                esac
                """#)
            try fixture.tool(
                "codesign",
                #"""
                printf 'codesign %s\n' "$*" >> "$FAKE_ROOT/calls"
                if [ "$1" = -dvvv ]; then
                    printf '%s\n' 'Authority=Developer ID Application: Fixture' 'Timestamp=fixture' 'flags=0x10000(runtime)'
                    case "$2" in
                        *.dmg) echo Identifier=com.alfredlabs.littleswitch.dmg ;;
                        *) echo Identifier=com.alfredlabs.littleswitch ;;
                    esac
                fi
                """#)
            try fixture.tool("xcrun", "printf 'xcrun %s\\n' \"$*\" >> \"$FAKE_ROOT/calls\"")
            try fixture.tool("spctl", "printf 'spctl %s\\n' \"$*\" >> \"$FAKE_ROOT/calls\"")
            try fixture.tool("lipo", "echo arm64")
            var overrides = ["TMPDIR": root.path + "/"]
            for name in ["hdiutil", "codesign", "xcrun", "spctl", "lipo"] {
                overrides["LITTLE_SWITCH_RELEASE_" + name.uppercased()] =
                    root.appendingPathComponent("bin/" + name).path
            }
            let result = try fixture.run("verify-dmg.sh", overrides: overrides)
            #expect(result.status == 0, "\(result.stderr)")
            let calls = try fixture.read("calls")
            #expect(calls.contains("hdiutil verify"))
            #expect(calls.contains("codesign --verify --strict"))
            #expect(calls.contains("codesign --verify --deep --strict"))
            #expect(calls.contains("xcrun stapler validate"))
            #expect(calls.contains("spctl --assess --type open"))
            #expect(calls.contains("spctl --assess --type exec"))
            #expect(calls.contains("hdiutil detach"))
            #expect(
                try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy {
                    !$0.hasPrefix("little-switch-mount.")
                })
        }
    }

    @Test("Mise serializes release stages and exposes an independent Homebrew retry")
    func taskOrdering() throws {
        let mise = try RepositoryFixture.text(".mise.toml")
        for name in ["release:bump", "release:dmg", "release:notarize", "release:verify", "release:homebrew"] {
            #expect(mise.contains("[tasks.\"\(name)\"]"))
        }
        #expect(
            mise.contains(
                "mise run release:dmg\nmise run release:notarize\nmise run release:verify\nmise run release:publish -- --push"
            ))
        #expect(mise.contains("run = \"./tools/release/publish-homebrew.sh\""))
        let common = try RepositoryFixture.text("tools/release/common.sh")
        for value in [
            "LITTLE_SWITCH_RELEASE_TESTING", "Developer ID Application:", "resolve-signing-identity.sh", ".signing.env",
            ".env",
        ] {
            #expect(common.contains(value))
        }
        let verification = try RepositoryFixture.text("tools/release/verify-dmg.sh")
        #expect(verification.contains("/bin/rmdir"))
        #expect(!verification.contains("/usr/bin/rmdir"))
    }
}
