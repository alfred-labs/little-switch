import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Desktop application location")
struct DesktopApplicationLocatorTests {
    @Test("Running and registered renamed applications are found by identity", arguments: DesktopApplication.allCases)
    func renamed(application: DesktopApplication) {
        let running = URL(filePath: "/Volumes/Work/Renamed.app")
        let registered = URL(filePath: "/Users/test/Tools/Registered.app")
        var runningURL: URL? = running
        let locator = DesktopApplicationLocator(
            homeDirectory: URL(filePath: "/Users/test"),
            runningApplication: { id in
                #expect(id == application.bundleIdentifier)
                return runningURL
            },
            registeredApplication: { _ in registered },
            bundleIdentifier: { _ in application.bundleIdentifier }
        )
        #expect(locator.applicationURL(for: application) == running)
        runningURL = nil
        #expect(locator.applicationURL(for: application) == registered)
    }

    @Test("A ChatGPT filename never substitutes for the Codex bundle identifier")
    func wrongIdentity() {
        let chatGPT = URL(filePath: "/Applications/ChatGPT.app")
        var installed = [chatGPT: "com.openai.chat"]
        let locator = DesktopApplicationLocator(
            homeDirectory: URL(filePath: "/Users/test"),
            runningApplication: { _ in chatGPT },
            registeredApplication: { _ in chatGPT },
            bundleIdentifier: { installed[$0] }
        )
        #expect(locator.applicationURL(for: .codex) == nil)
        installed[chatGPT] = "com.openai.codex"
        #expect(locator.applicationURL(for: .codex) == chatGPT)
        installed.removeAll()
        #expect(locator.applicationURL(for: .codex) == nil)
    }

    @Test(
        "Unregistered installs in the user's Applications folder are discovered", arguments: DesktopApplication.allCases
    )
    func userApplications(application: DesktopApplication) {
        let home = URL(filePath: "/Users/test")
        let name: String =
            switch application {
            case .claude: "Claude.app"
            case .codex: "Codex.app"
            case .openCode: "OpenCode.app"
            }
        let installed = home.appending(path: "Applications/\(name)")
        let locator = DesktopApplicationLocator(
            homeDirectory: home,
            runningApplication: { _ in nil },
            registeredApplication: { _ in nil },
            bundleIdentifier: { $0.path == installed.path ? application.bundleIdentifier : nil }
        )
        #expect(locator.applicationURL(for: application)?.path == installed.path)
    }
}
