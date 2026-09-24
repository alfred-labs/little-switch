import Foundation
import Testing

@Suite("Bundled Sparkle update copy")
struct SparkleUpdateCopyTests {
    private let summaryKey = "%@ %@ is now available—you have %@. Would you like to download it now?"

    @Test(
        "The bundled announcement omits the installed version without changing other updater text",
        arguments: [false, true])
    func conciseAnnouncement(binary: Bool) throws {
        try withTemporaryDirectory { root in
            let fixture = try AppBuildFixture(root: root)
            let originals = try ["Base", "fr"].map { language in
                try strings(
                    root.appendingPathComponent(
                        "\(fixture.sparkleDirectory)/Resources/\(language).lproj/Sparkle.strings"))
            }
            if binary {
                for (index, language) in ["Base", "fr"].enumerated() {
                    try PropertyListSerialization.data(fromPropertyList: originals[index], format: .binary, options: 0)
                        .write(
                            to: root.appendingPathComponent(
                                "\(fixture.sparkleDirectory)/Resources/\(language).lproj/Sparkle.strings"))
                }
            }
            let result = try fixture.run()
            try #require(result.status == 0, "\(result.stdout)\n\(result.stderr)")
            for (index, language) in ["Base", "fr"].enumerated() {
                let bundled = try strings(
                    root.appendingPathComponent(
                        "\(fixture.bundleDirectory)/Frameworks/Sparkle.framework/Resources/\(language).lproj/Sparkle.strings"
                    ))
                var expected = originals[index]
                expected[summaryKey] = language == "Base" ? "%1$@ %2$@ is now available." : "%1$@ %2$@ est disponible."
                #expect(bundled == expected)
                let format = try #require(bundled[summaryKey])
                #expect(
                    String(format: format, "LittleSwitch", "1.2.4", "0.6.3")
                        == (language == "Base"
                            ? "LittleSwitch 1.2.4 is now available." : "LittleSwitch 1.2.4 est disponible."))
                #expect(
                    try strings(
                        root.appendingPathComponent(
                            "\(fixture.sparkleDirectory)/Resources/\(language).lproj/Sparkle.strings"))
                        == originals[index])
            }
        }
    }

    @Test("A changed upstream summary key stops bundling instead of silently keeping the old text")
    func changedUpstreamKey() throws {
        try withTemporaryDirectory { root in
            let fixture = try AppBuildFixture(root: root)
            try fixture.write(
                "\(fixture.sparkleDirectory)/Resources/fr.lproj/Sparkle.strings", "\"Install Update\" = \"Installer\";")
            let result = try fixture.run()
            #expect(result.status != 0)
            #expect(result.stderr.contains("Sparkle") && result.stderr.contains("fr.lproj"))
            #expect(
                try strings(
                    root.appendingPathComponent(
                        "\(fixture.bundleDirectory)/Frameworks/Sparkle.framework/Resources/Base.lproj/Sparkle.strings"))
                    == strings(
                        root.appendingPathComponent("\(fixture.sparkleDirectory)/Resources/Base.lproj/Sparkle.strings"))
            )
        }
    }

    @Test("Bundle verification rejects an uncustomized announcement", arguments: ["Base", "fr"])
    func staleAnnouncement(language: String) throws {
        try withTemporaryDirectory { root in
            let fixture = try AppBuildFixture(root: root)
            let build = try fixture.run()
            try #require(build.status == 0, "\(build.stderr)")
            try fixture.write(
                "\(fixture.bundleDirectory)/Frameworks/Sparkle.framework/Resources/\(language).lproj/Sparkle.strings",
                "\"\(summaryKey)\" = \"Outdated summary\";")
            let result = try fixture.run("tools/ci/verify-bundle.sh")
            #expect(result.status != 0)
            #expect(result.stderr.contains("Sparkle") && result.stderr.contains("\(language).lproj"))
            #expect(
                try strings(
                    root.appendingPathComponent(
                        "\(fixture.bundleDirectory)/Frameworks/Sparkle.framework/Resources/\(language).lproj/Sparkle.strings"
                    ))
                    == [summaryKey: "Outdated summary"])
        }
    }

    @Test("Unsigned development builds reseal the modified framework with an ad-hoc signature")
    func developmentSignature() throws {
        try withTemporaryDirectory { root in
            let fixture = try AppBuildFixture(root: root)
            let result = try fixture.run()
            try #require(result.status == 0, "\(result.stderr)")
            #expect(
                try fixture.read("calls").contains(
                    "codesign\tcodesign\t--force\t--sign\t-\t\(root.path)/\(fixture.bundleDirectory)/Frameworks/Sparkle.framework\n"
                ))
        }
    }

    private func strings(_ url: URL) throws -> [String: String] {
        try #require(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    }
}
