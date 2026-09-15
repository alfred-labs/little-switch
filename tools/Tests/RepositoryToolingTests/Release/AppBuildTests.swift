import Foundation
import Testing

@Suite("Application build artifacts")
struct AppBuildTests {
    @Test("The bundle contains the current executable and its localization resources")
    func currentArtifacts() throws {
        try withTemporaryDirectory { root in
            let fixture = try AppBuildFixture(root: root)
            let result = try fixture.run()
            try #require(result.status == 0, "\(result.stdout)\n\(result.stderr)")
            #expect(try fixture.read("\(fixture.bundleDirectory)/MacOS/LittleSwitch") == "current executable\n")
            for target in ["LittleSwitchCore", "LittleSwitchUI"] {
                let resource = "LittleSwitch_\(target).bundle/Contents/Resources/fr.lproj/Localizable.strings"
                #expect(
                    try fixture.read("\(fixture.bundleDirectory)/Resources/\(resource)")
                        == fixture.read("\(fixture.productDirectory)/\(resource)"))
            }
            let calls = try fixture.read("calls").split(separator: "\n").filter { $0.hasPrefix("swift\t") }
            try #require(calls.count == 2)
            #expect(String(calls[1]) == String(calls[0]) + "\t--show-bin-path")
            #expect(calls[0].contains("--build-system\tswiftbuild"))
            #expect(calls[0].contains("--scratch-path\t\(root.path)/.build"))
            #expect(calls[0].contains("--configuration\trelease"))
            #expect(calls[0].contains("--triple\tarm64-apple-macosx14.0"))
            #expect(calls[0].contains("-warnings-as-errors"))
        }
    }

    @Test(
        "Failed compilation or product lookup preserves the previous bundle and diagnostic", arguments: [false, true])
    func commandFailures(pathLookup: Bool) throws {
        try withTemporaryDirectory { root in
            let fixture = try AppBuildFixture(root: root)
            let result = try fixture.run(overrides: [pathLookup ? "FAKE_PATH_STATUS" : "FAKE_BUILD_STATUS": "7"])
            #expect(result.status == 7)
            #expect(result.stderr.contains(pathLookup ? "path lookup failed" : "compilation failed"))
            #expect(try fixture.read("\(fixture.bundleDirectory)/previous-bundle") == "preserved on failure\n")
        }
    }

    @Test("Missing current products never use the stale executable", arguments: [false, true])
    func missingProducts(resource: Bool) throws {
        try withTemporaryDirectory { root in
            let fixture = try AppBuildFixture(root: root)
            let path = resource ? "LittleSwitch_LittleSwitchUI.bundle" : "LittleSwitch"
            try FileManager.default.removeItem(at: root.appendingPathComponent("\(fixture.productDirectory)/\(path)"))
            let result = try fixture.run()
            #expect(result.status != 0)
            #expect(result.stderr.contains(path))
            #expect(try fixture.read("\(fixture.bundleDirectory)/previous-bundle") == "preserved on failure\n")
        }
    }

    @Test("Bundle verification rejects a stale executable even when its Git tag is unchanged")
    func staleBundle() throws {
        try withTemporaryDirectory { root in
            let fixture = try AppBuildFixture(root: root)
            let build = try fixture.run()
            try #require(build.status == 0, "\(build.stderr)")
            let current = try fixture.run("tools/ci/verify-bundle.sh")
            #expect(current.status == 0, "\(current.stderr)")
            try fixture.write("\(fixture.bundleDirectory)/MacOS/LittleSwitch", "stale executable\n", executable: true)
            let stale = try fixture.run("tools/ci/verify-bundle.sh")
            #expect(stale.status != 0)
            #expect(stale.stderr.contains("does not match the current release product"))
        }
    }

    @Test("Bundle verification rejects missing or stale resource bundles", arguments: [false, true])
    func staleResources(missing: Bool) throws {
        try withTemporaryDirectory { root in
            let fixture = try AppBuildFixture(root: root)
            let build = try fixture.run()
            try #require(build.status == 0, "\(build.stderr)")
            let resource = "\(fixture.bundleDirectory)/Resources/LittleSwitch_LittleSwitchUI.bundle"
            if missing {
                try FileManager.default.removeItem(at: root.appendingPathComponent(resource))
            } else {
                try fixture.write("\(resource)/Contents/Resources/fr.lproj/Localizable.strings", "stale translation")
            }
            let result = try fixture.run("tools/ci/verify-bundle.sh")
            #expect(result.status != 0)
            #expect(result.stderr.contains("LittleSwitch_LittleSwitchUI.bundle"))
        }
    }
}
