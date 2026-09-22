import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Desktop application availability and launch")
struct DesktopApplicationManagerTests {
    @Test("Availability follows installation and only Claude's organization restriction")
    func availability() {
        var installed: Set<DesktopApplication> = [.claude, .openCode]
        var managed = false
        let manager = DesktopApplicationManager(
            locateApplication: { installed.contains($0) ? URL(filePath: "/Applications/Test.app") : nil },
            isClaudeOrganizationManaged: { managed },
            openApplication: { _ in Issue.record("Reading availability must not open an app") }
        )
        #expect(manager.availability() == .init(claude: .available, openCode: .available))
        managed = true
        #expect(manager.availability() == .init(claude: .organizationManaged, openCode: .available))
        installed = [.codex]
        #expect(manager.availability() == .init(codex: .available))
    }

    @Test(
        "Opening uses the freshly located app without quitting or changing profiles",
        arguments: DesktopApplication.allCases)
    func open(application: DesktopApplication) async throws {
        let original = URL(filePath: "/Applications/Original.app")
        let moved = URL(filePath: "/Users/test/Applications/Moved.app")
        var location: URL? = original
        var opened: [URL] = []
        let manager = DesktopApplicationManager(
            locateApplication: { requested in
                #expect(requested == application)
                return location
            },
            isClaudeOrganizationManaged: { false },
            openApplication: { opened.append($0) }
        )
        location = moved
        try await manager.open(application)
        #expect(opened == [moved])
        location = nil
        await #expect(throws: DesktopApplicationLaunchError.notInstalled(application)) {
            try await manager.open(application)
        }
        #expect(opened == [moved])
    }

    @Test("A policy arriving after detection prevents opening Claude")
    func managedLaunch() async throws {
        var managed = false
        var opened: [URL] = []
        let url = URL(filePath: "/Applications/Claude.app")
        let manager = DesktopApplicationManager(
            locateApplication: { _ in url },
            isClaudeOrganizationManaged: { managed },
            openApplication: { opened.append($0) }
        )
        #expect(manager.availability().claude == .available)
        managed = true
        await #expect(throws: DesktopApplicationLaunchError.organizationManaged) {
            try await manager.open(.claude)
        }
        #expect(opened.isEmpty)
        try await manager.open(.codex)
        #expect(opened == [url])
    }

    @Test("Launch errors are controlled and do not disclose filesystem details")
    func failure() async {
        let manager = DesktopApplicationManager(
            locateApplication: { _ in URL(filePath: "/private/user/Application.app") },
            isClaudeOrganizationManaged: { false },
            openApplication: { _ in throw CocoaError(.fileNoSuchFile) }
        )
        await #expect(throws: DesktopApplicationLaunchError.launchFailed(.openCode)) {
            try await manager.open(.openCode)
        }
        for application in DesktopApplication.allCases {
            #expect(
                DesktopApplicationLaunchError.notInstalled(application).errorDescription?.contains(
                    application.displayName) == true)
            #expect(
                DesktopApplicationLaunchError.launchFailed(application).errorDescription?.contains(
                    application.displayName) == true)
        }
        #expect(DesktopApplicationLaunchError.organizationManaged.errorDescription?.isEmpty == false)
    }

    @Test("Launch cancellation is not reported as an application failure")
    func cancelledLaunch() async {
        let manager = DesktopApplicationManager(
            locateApplication: { _ in URL(filePath: "/Applications/Codex.app") },
            isClaudeOrganizationManaged: { false },
            openApplication: { _ in throw CancellationError() }
        )
        await #expect(throws: CancellationError.self) { try await manager.open(.codex) }
    }
}
