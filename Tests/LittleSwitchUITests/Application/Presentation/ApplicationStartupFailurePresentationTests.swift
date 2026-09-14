import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Application startup failure presentation")
struct StartupFailurePresentationTests {
    @Test("A failed coordinator startup applies its loaded snapshot before synchronizing the menu")
    func loadedSnapshotPrecedesFailurePresentation() {
        let provider = Provider(
            name: "Loaded provider",
            baseURL: "https://loaded.example",
            authMode: .bearer,
            models: [DiscoveredModel(id: "loaded-model")],
            status: .ready,
            maximumParallelRequests: 3
        )
        var configuration = AppConfiguration()
        configuration.providers = [provider]
        let snapshot = CoordinatorSnapshot(
            configuration: configuration,
            requestCount: 7,
            claudeRequestCount: 4,
            codexRequestCount: 3
        )
        let model = AppModel()
        model.isBusy = true
        var synchronizedMenu: GatewayActivityPresentation.Menu?

        ApplicationStartupFailurePresentation.apply(
            snapshot: snapshot,
            message: "Gateway failed",
            to: model
        ) {
            synchronizedMenu = model.gatewayActivityPresentation.menu
        }

        #expect(model.configuration == configuration)
        #expect(model.requestCount == 7)
        #expect(model.claudeRequestCount == 4)
        #expect(model.codexRequestCount == 3)
        #expect(model.gatewayActivity == .unavailable)
        #expect(model.errorMessage == "Gateway failed")
        #expect(!model.isBusy)
        #expect(synchronizedMenu?.title == "Gateway unavailable")
        #expect(synchronizedMenu?.accessibilityValue == "Gateway unavailable")
    }

    @Test("An early startup failure preserves the shell model and synchronizes unavailable state")
    func earlyFailureWithoutSnapshot() {
        var configuration = AppConfiguration()
        configuration.autoMode = true
        let model = AppModel(snapshot: CoordinatorSnapshot(configuration: configuration))
        model.isBusy = true
        var synchronizedActivity: GatewayActivitySnapshot?

        ApplicationStartupFailurePresentation.apply(
            snapshot: nil,
            message: "Ownership failed",
            to: model
        ) {
            synchronizedActivity = model.gatewayActivity
        }

        #expect(model.configuration == configuration)
        #expect(model.gatewayActivity == .unavailable)
        #expect(model.errorMessage == "Ownership failed")
        #expect(!model.isBusy)
        #expect(synchronizedActivity == .unavailable)
    }
}
