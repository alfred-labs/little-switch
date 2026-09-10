import Testing

@testable import LittleSwitchCore

@Suite("Application build tag")
struct ApplicationBuildTests {
    @Test("An untagged or malformed bundle falls back to development")
    func developmentFallbacks() {
        #expect(ApplicationBuild.developmentTag == "development")
        #expect(ApplicationBuild.tag(infoDictionary: nil) == "development")
        #expect(ApplicationBuild.tag(infoDictionary: [:]) == "development")
        #expect(
            ApplicationBuild.tag(infoDictionary: [ApplicationBuild.infoDictionaryKey: ""])
                == "development"
        )
        #expect(
            ApplicationBuild.tag(infoDictionary: [ApplicationBuild.infoDictionaryKey: 7])
                == "development"
        )
    }

    @Test("A tagged bundle reports its git describe output")
    func taggedBundle() {
        #expect(
            ApplicationBuild.tag(
                infoDictionary: [ApplicationBuild.infoDictionaryKey: "v1.2-14-g1a2b3c4-dirty"]
            ) == "v1.2-14-g1a2b3c4-dirty"
        )
    }

    @Test("The test runner runs outside a tagged app bundle")
    func currentTagOutsideAppBundle() {
        #expect(ApplicationBuild.currentTag == "development")
    }
}
