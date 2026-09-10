import Foundation
import Testing

@Suite("Application delegate startup")
struct DelegateStartupTests {
    @Test("Termination waits for the complete owned startup before coordinator shutdown")
    func terminationWaitsForOwnedStartup() throws {
        let source = try uiSource(named: "Application/Lifecycle/LittleSwitchApplicationDelegate.swift")
        let ownedStart = try #require(
            source.range(of: "private func startOwnedApplication() async")
        )
        let shell = try #require(
            source.range(
                of: "private func startApplicationShell()",
                range: ownedStart.upperBound..<source.endIndex
            )
        )
        let ownedBody = String(source[ownedStart.lowerBound..<shell.lowerBound])
        let trafficStart = try #require(ownedBody.range(of: "await trafficStore.start()"))
        let coordinatorStart = try #require(ownedBody.range(of: "await start()"))
        #expect(trafficStart.lowerBound < coordinatorStart.lowerBound)
        #expect(!ownedBody.contains("\n        Task {"))

        let cancellation = try #require(source.range(of: "startupTask?.cancel()"))
        let startupCompletion = try #require(
            source.range(
                of: "await startupTask?.value",
                range: cancellation.upperBound..<source.endIndex
            )
        )
        let coordinatorShutdown = try #require(
            source.range(
                of: "await coordinator?.shutdown(mode: terminationState.mode)",
                range: startupCompletion.upperBound..<source.endIndex
            )
        )
        #expect(cancellation.lowerBound < startupCompletion.lowerBound)
        #expect(startupCompletion.lowerBound < coordinatorShutdown.lowerBound)
    }

    @Test("Every delegate startup failure synchronizes the gateway menu")
    func startupFailureSynchronization() throws {
        let source = try uiSource(named: "Application/Lifecycle/LittleSwitchApplicationDelegate.swift")
        let presentation = try uiSource(
            named: "Application/Presentation/LittleSwitchApplicationDelegatePresentation.swift"
        )
        let acquisitionFailure = try #require(
            source.range(of: "Could not replace the existing LittleSwitch instance.")
        )
        let ownedStart = try #require(
            source.range(of: "private func startOwnedApplication() async")
        )
        let runtimeStart = try #require(source.range(of: "private func start() async"))
        let snapshotFailure = try #require(
            source.range(
                of: "let snapshot = await coordinator.snapshot()",
                range: runtimeStart.upperBound..<source.endIndex
            )
        )

        #expect(source[..<ownedStart.lowerBound].contains("presentStartupFailure("))
        #expect(
            source[ownedStart.lowerBound..<runtimeStart.lowerBound]
                .contains("presentStartupFailure(")
        )
        #expect(acquisitionFailure.lowerBound < ownedStart.lowerBound)
        #expect(runtimeStart.lowerBound < snapshotFailure.lowerBound)
        #expect(presentation.contains("statusItemController?.refreshGatewayActivity()"))
    }

    private func uiSource(named filename: String) throws -> String {
        let repository = RepositorySources.root
        return try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/LittleSwitchUI/\(filename)"
            ),
            encoding: .utf8
        )
    }
}
