import Foundation
import Testing

@Suite("Bundled Swift compatibility runtimes")
struct SwiftRuntimeBundleTests {
    @Test("The executable's required compatibility runtime is included in the application")
    func includesRuntime() throws {
        try withTemporaryDirectory { root in
            let fixture = try AppBuildFixture(root: root)
            let result = try fixture.run()
            try #require(result.status == 0, "\(result.stderr)")
            let runtime = "\(fixture.bundleDirectory)/Frameworks/libswiftCompatibilitySpan.dylib"
            try #require(FileManager.default.fileExists(atPath: root.appendingPathComponent(runtime).path))
            #expect(try fixture.read(runtime) == "swift compatibility runtime\n")
        }
    }

    @Test("Verification rejects an application that omits a required Swift runtime")
    func rejectsMissingRuntime() throws {
        try withTemporaryDirectory { root in
            let fixture = try AppBuildFixture(root: root)
            let build = try fixture.run()
            try #require(build.status == 0, "\(build.stderr)")
            let runtime = root.appendingPathComponent(
                "\(fixture.bundleDirectory)/Frameworks/libswiftCompatibilitySpan.dylib")
            if FileManager.default.fileExists(atPath: runtime.path) {
                try FileManager.default.removeItem(at: runtime)
            }
            let result = try fixture.run("tools/ci/verify-bundle.sh")
            #expect(result.status != 0)
            #expect(result.stderr.contains("libswiftCompatibilitySpan.dylib"))
        }
    }
}
