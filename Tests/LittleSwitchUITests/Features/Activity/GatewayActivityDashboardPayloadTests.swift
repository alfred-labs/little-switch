import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Gateway activity dashboard payload")
struct GatewayActivityDashboardPayloadTests {
    private struct Fixture {
        let presentation: GatewayActivityPresentation
    }

    private struct VisibilityCase {
        let configuredProviders: [Provider]
        let snapshots: [ProviderRequestPoolProviderSnapshot]
        let isVisible: Bool
    }

    @Test(
        "Dashboard visibility requires a configured provider or a removed provider still in the pool",
        arguments: [0, 3]
    )
    func dashboardVisibility(runningCount: Int) {
        let provider = Provider(name: "Configured", baseURL: "https://example.com", authMode: .none)
        let live = ProviderRequestPoolProviderSnapshot(
            id: provider.id,
            displayName: provider.name,
            maximumParallelRequests: 4,
            runningCount: runningCount,
            waitingCount: 0,
            retainedWaitingBytes: 0,
            oldestWaitDuration: nil,
            isRemoved: false
        )
        let removed = ProviderRequestPoolProviderSnapshot(
            id: provider.id,
            displayName: provider.name,
            maximumParallelRequests: 4,
            runningCount: runningCount,
            waitingCount: 0,
            retainedWaitingBytes: 0,
            oldestWaitDuration: nil,
            isRemoved: true
        )
        let cases: [VisibilityCase] = [
            .init(configuredProviders: [], snapshots: [], isVisible: false),
            .init(configuredProviders: [], snapshots: [live], isVisible: false),
            .init(configuredProviders: [], snapshots: [removed], isVisible: true),
            .init(configuredProviders: [], snapshots: [live, removed], isVisible: true),
            .init(configuredProviders: [provider], snapshots: [], isVisible: true),
            .init(configuredProviders: [provider], snapshots: [live], isVisible: true),
            .init(configuredProviders: [provider], snapshots: [removed], isVisible: true),
        ]
        for scenario in cases {
            let presentation = GatewayActivityPresentation(
                activity: .running(
                    ProviderRequestPoolSnapshot(
                        totalRunning: runningCount, totalWaiting: 0, providers: scenario.snapshots
                    )
                ),
                providers: scenario.configuredProviders
            )
            let expected: GatewayActivityPresentation.Menu.Dashboard? =
                scenario.isVisible ? .init(runningCount: runningCount, waitingCount: 0, stats: nil) : nil
            #expect(presentation.menu.dashboard == expected)
        }
    }

    @Test("The running dashboard carries complete live counts and lifecycle states omit it")
    func runningDashboardAndLifecycleStates() throws {
        let providerID = UUID()
        let presentation = GatewayActivityPresentation(
            activity: .running(
                ProviderRequestPoolSnapshot(
                    totalRunning: 2,
                    totalWaiting: 1,
                    providers: [
                        ProviderRequestPoolProviderSnapshot(
                            id: providerID,
                            displayName: "z.ai",
                            maximumParallelRequests: 4,
                            runningCount: 2,
                            waitingCount: 1,
                            retainedWaitingBytes: 0,
                            oldestWaitDuration: nil,
                            isRemoved: false
                        )
                    ]
                )
            ),
            providers: [
                Provider(
                    id: providerID,
                    name: "z.ai",
                    baseURL: "https://example.com",
                    authMode: .none,
                    models: []
                )
            ]
        )
        let dashboard = try #require(presentation.menu.dashboard)
        #expect(dashboard == .init(runningCount: 2, waitingCount: 1, stats: nil))

        let idleWithoutProviders = GatewayActivityPresentation(
            activity: .running(
                ProviderRequestPoolSnapshot(
                    totalRunning: 0,
                    totalWaiting: 0,
                    providers: []
                )
            ),
            providers: []
        )
        #expect(idleWithoutProviders.menu.dashboard == nil)

        let starting = GatewayActivityPresentation(activity: .starting, providers: [])
        #expect(starting.menu.dashboard == nil)

        let unavailable = GatewayActivityPresentation(
            activity: .unavailable,
            providers: []
        )
        #expect(unavailable.menu.dashboard == nil)
    }
}
