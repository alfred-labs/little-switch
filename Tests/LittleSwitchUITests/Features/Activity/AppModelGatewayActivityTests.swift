import Foundation
import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("App model gateway activity")
struct AppModelGatewayActivityTests {
    @Test("Gateway activity starts truthfully without presenting live counts")
    func initialGatewayActivity() {
        let provider = activityProvider(name: "Alpha", limit: 2)
        let model = AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: AppConfiguration(providers: [provider])
            )
        )

        #expect(model.gatewayActivity == .starting)
        #expect(model.gatewayActivityPresentation.menu.title == "Starting gateway…")
        #expect(model.gatewayActivityPresentation.menu.dashboard == nil)
    }

    @Test("Focused gateway activity updates only activity presentation")
    func focusedGatewayActivityUpdate() {
        let provider = activityProvider(name: "Alpha", limit: 2)
        let configuration = AppConfiguration(
            providers: [provider],
            autoMode: false,
            connected: true,
            codex: CodexConfiguration(connected: true)
        )
        let model = AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: configuration,
                requestCount: 12,
                claudeRequestCount: 7,
                codexRequestCount: 5,
                proxyRunning: true,
                hasPendingCodexChanges: true,
                claudeCodeStatus: .needsAttention,
                hasPendingClaudeCodeChanges: true,
                claudeCodeMappedRouteIDs: ["claude-sonnet-5"],
                openCodeStatus: .needsAttention,
                hasPendingOpenCodeChanges: true
            )
        )
        model.isBusy = true
        model.errorMessage = "Keep this error"
        model.launchAtLoginStatus = .requiresApproval
        model.isChangingLaunchAtLogin = true
        model.selectedSection = .providers
        let pool = activityPoolSnapshot(
            running: 1,
            waiting: 1,
            provider: provider,
            maximumParallelRequests: 2
        )

        model.updateGatewayActivity(.running(pool))

        #expect(model.gatewayActivity == .running(pool))
        #expect(model.gatewayActivityPresentation.menu.title == "1 running · 1 waiting")
        #expect(model.gatewayActivityPresentation.menu.dashboard == .init(runningCount: 1, waitingCount: 1, stats: nil))
        #expect(model.configuration == configuration)
        #expect(model.requestCount == 12)
        #expect(model.claudeRequestCount == 7)
        #expect(model.codexRequestCount == 5)
        #expect(model.proxyRunning)
        #expect(model.hasPendingCodexChanges)
        #expect(model.claudeCodeStatus == .needsAttention)
        #expect(model.hasPendingClaudeCodeChanges)
        #expect(model.claudeCodeMappedRouteIDs == ["claude-sonnet-5"])
        #expect(model.openCodeStatus == .needsAttention)
        #expect(model.hasPendingOpenCodeChanges)
        #expect(model.isBusy)
        #expect(model.errorMessage == "Keep this error")
        #expect(model.launchAtLoginStatus == .requiresApproval)
        #expect(model.isChangingLaunchAtLogin)
        #expect(model.selectedSection == .providers)
    }

    @Test("Polling updates refresh counts and activity without replacing presentation state")
    func pollingUpdate() {
        let provider = activityProvider(name: "Alpha", limit: 2)
        let configuration = AppConfiguration(providers: [provider], connected: true)
        let model = AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: configuration,
                requestCount: 1,
                claudeRequestCount: 1
            )
        )
        model.isBusy = true
        model.errorMessage = "Keep this error"
        model.selectedSection = .providers
        let pool = activityPoolSnapshot(
            running: 2,
            waiting: 3,
            provider: provider,
            maximumParallelRequests: 2
        )
        let update = GatewayActivityPollingUpdate(
            snapshot: CoordinatorSnapshot(
                configuration: AppConfiguration(),
                requestCount: 8,
                claudeRequestCount: 5,
                codexRequestCount: 3
            ),
            activity: .running(pool)
        )

        update.apply(to: model)

        #expect(model.requestCount == 8)
        #expect(model.claudeRequestCount == 5)
        #expect(model.codexRequestCount == 3)
        #expect(model.gatewayActivity == .running(pool))
        #expect(model.configuration == configuration)
        #expect(model.isBusy)
        #expect(model.errorMessage == "Keep this error")
        #expect(model.selectedSection == .providers)
    }

    @Test("A polled usage summary reaches the menu dashboard")
    func applyGatewayUsage() {
        let provider = activityProvider(name: "Alpha", limit: 2)
        let model = AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: AppConfiguration(providers: [provider])
            )
        )
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        var history = GatewayUsageHistory()
        history.fold(
            GatewayUsageEvent(
                finishedAt: now,
                outcome: .succeeded,
                client: .claude,
                routeID: "claude-opus-5",
                providerName: "Alpha",
                durationMilliseconds: 640,
                usage: GatewayUsageTotals(inputTokens: 300, outputTokens: 40)
            )
        )
        let update = GatewayActivityPollingUpdate(
            snapshot: CoordinatorSnapshot(configuration: AppConfiguration(providers: [provider])),
            activity: .running(
                activityPoolSnapshot(
                    running: 1,
                    waiting: 0,
                    provider: provider,
                    maximumParallelRequests: 2
                )
            ),
            usage: GatewayUsageSummary(history: history, now: now)
        )

        update.apply(to: model)

        #expect(model.gatewayUsage?.today.requests == 1)
        let stats = model.gatewayActivityPresentation.menu.dashboard?.stats
        let period = stats?.period(at: nil)
        #expect(period?.metrics[3].title == "Requests")
        #expect(period?.metrics[3].value == "1")
        #expect(period?.metrics[3].isLeading == true)
        #expect(period?.metrics[0].value == "300")
        #expect(period?.tokenTotal == "340")
        #expect(stats?.points.last == 340)
        #expect(model.gatewayActivityPresentation.menu.dashboard?.runningCount == 1)
        #expect(model.gatewayActivityPresentation.menu.dashboard?.waitingCount == 0)

        model.updateGatewayUsage(nil)
        #expect(model.gatewayActivityPresentation.menu.dashboard?.stats == nil)
    }

    @Test("Repeated equal updates leave the learned state untouched")
    func dedupedLearnedStateUpdates() {
        let provider = activityProvider(name: "Alpha", limit: 2)
        let model = AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: AppConfiguration(providers: [provider])
            )
        )
        let pool = activityPoolSnapshot(
            running: 1,
            waiting: 0,
            provider: provider,
            maximumParallelRequests: 2
        )

        model.updateGatewayActivity(.running(pool))
        model.updateGatewayActivity(.running(pool))
        #expect(model.gatewayActivity == .running(pool))

        model.updateResponsesWireVerdicts([provider.id: true])
        model.updateResponsesWireVerdicts([provider.id: true])
        #expect(model.responsesWireVerdicts == [provider.id: true])

        model.updateCredentialRefreshFailures([provider.id: "The credential script exited with status 1."])
        model.updateCredentialRefreshFailures([provider.id: "The credential script exited with status 1."])
        #expect(model.credentialRefreshFailures == [provider.id: "The credential script exited with status 1."])
    }

    @Test("Full snapshots retain newer activity while replacing provider configuration")
    func applyRetainsGatewayActivity() {
        let provider = activityProvider(name: "Alpha", limit: 2)
        let model = AppModel(
            snapshot: CoordinatorSnapshot(
                configuration: AppConfiguration(providers: [provider])
            )
        )
        let pool = activityPoolSnapshot(
            running: 3,
            waiting: 0,
            provider: provider,
            maximumParallelRequests: 2
        )
        model.updateGatewayActivity(.running(pool))
        var renamed = provider
        renamed.name = "Renamed"
        renamed.maximumParallelRequests = 5

        model.apply(
            CoordinatorSnapshot(
                configuration: AppConfiguration(providers: [renamed]),
                requestCount: 9
            )
        )

        #expect(model.gatewayActivity == .running(pool))
        #expect(model.requestCount == 9)
        #expect(model.configuration.providers == [renamed])
        #expect(model.gatewayActivityPresentation.menu.dashboard == .init(runningCount: 3, waitingCount: 0, stats: nil))
    }
}

private func activityProvider(name: String, limit: Int) -> Provider {
    Provider(
        id: activityProviderID,
        name: name,
        baseURL: "https://example.com",
        authMode: .none,
        maximumParallelRequests: limit
    )
}

private func activityPoolSnapshot(
    running: Int,
    waiting: Int,
    provider: Provider,
    maximumParallelRequests: Int
) -> ProviderRequestPoolSnapshot {
    ProviderRequestPoolSnapshot(
        totalRunning: running,
        totalWaiting: waiting,
        providers: [
            ProviderRequestPoolProviderSnapshot(
                id: provider.id,
                displayName: provider.name,
                maximumParallelRequests: maximumParallelRequests,
                runningCount: running,
                waitingCount: waiting,
                retainedWaitingBytes: waiting,
                oldestWaitDuration: waiting > 0 ? .seconds(1) : nil,
                isRemoved: false
            )
        ]
    )
}

private let activityProviderID = UUID(
    uuid: (9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9)
)
