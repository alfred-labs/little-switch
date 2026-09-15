import Foundation
import Testing

@Suite("Delivered application resources")
struct DeliveredBundleTests {
    @Test("Verification checks the delivered bundle even when the local build is complete", arguments: [false, true])
    func deliveredResources(missing: Bool) throws {
        try withTemporaryDirectory { root in
            let fixture = try AppBuildFixture(root: root)
            let build = try fixture.run()
            try #require(build.status == 0, "\(build.stderr)")
            let delivered = root.appendingPathComponent("Delivered.app")
            try FileManager.default.copyItem(
                at: root.appendingPathComponent("build/LittleSwitch.app"), to: delivered)
            if missing {
                try FileManager.default.removeItem(
                    at: delivered.appendingPathComponent("Contents/Resources/LittleSwitch_LittleSwitchUI.bundle"))
            }
            let result = try fixture.run("tools/ci/verify-bundle.sh", arguments: [delivered.path])
            #expect((result.status == 0) == !missing, "\(result.stdout)\n\(result.stderr)")
            if missing {
                #expect(result.stderr.contains("LittleSwitch_LittleSwitchUI.bundle"))
            } else {
                #expect(result.stdout.contains("Verified \(delivered.path)"))
            }
        }
    }
}
