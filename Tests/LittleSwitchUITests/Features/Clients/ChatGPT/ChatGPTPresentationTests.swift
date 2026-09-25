import LittleSwitchCommon
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("ChatGPT settings presentation")
struct ChatGPTPresentationTests {
    @Test("The Chat choice is required and independent of Codex exposure")
    func independentChoice() {
        let provider = Provider(
            name: "Synthetic",
            baseURL: "http://127.0.0.1:12345",
            authMode: .none,
            models: [DiscoveredModel(id: "chat")],
            status: .ready
        )
        var snapshot = CoordinatorSnapshot(configuration: .init(providers: [provider]))
        let model = AppModel(snapshot: snapshot)
        #expect(!model.canOpenChatGPT)
        #expect(!model.prepareDesktopConnection())
        #expect(model.isChoosingChatModelForConnection)
        #expect(model.selectedSection == .chatGPT)
        let choice = ModelMapping(providerID: provider.id, modelID: "chat")
        snapshot.configuration.chatgpt.model = choice
        snapshot.configuration.codex.excludedModels = [choice]
        model.apply(snapshot)
        #expect(model.canOpenChatGPT)
        #expect(model.prepareDesktopConnection())
        snapshot.hasPendingChatGPTChanges = true
        model.apply(snapshot)
        #expect(!model.canOpenChatGPT)
        #expect(model.canApplyChatGPTSettings)
        #expect(model.pendingChangeNames.contains("ChatGPT"))
        snapshot.configuration.chatgpt.model = .init(providerID: provider.id, modelID: "missing")
        model.apply(snapshot)
        #expect(!model.canOpenChatGPT)
    }

    @Test("Polling publishes lifecycle progress and rejects an older response after an action")
    func polling() {
        let model = AppModel()
        var snapshot = CoordinatorSnapshot(configuration: .init(), monitoringSnapshotSequence: 1)
        snapshot.chatGPTStatus = .connecting
        GatewayActivityPollingUpdate(snapshot: snapshot, activity: .starting).apply(to: model)
        #expect(model.chatGPTStatus == .connecting)
        var completed = snapshot
        completed.chatGPTStatus = .connected
        completed.monitoringSnapshotSequence = 2
        model.apply(completed)
        GatewayActivityPollingUpdate(snapshot: snapshot, activity: .starting).apply(to: model)
        #expect(model.chatGPTStatus == .connected)
    }

    @Test("ChatGPT is adjacent to Codex and snapshot state drives its actions")
    func presentation() {
        #expect(AppModel.SidebarGroup.apps.sections == [.claude, .codex, .chatGPT, .openCode])
        var snapshot = CoordinatorSnapshot(configuration: .init())
        let model = AppModel(snapshot: snapshot)
        #expect(!model.canOpenChatGPT)
        #expect(!model.canDisconnectChatGPT)
        snapshot.configuration.chatgpt.connected = true
        snapshot.chatGPTStatus = .ready
        model.apply(snapshot)
        #expect(model.chatGPTStatus == .ready)
        #expect(model.canDisconnectChatGPT)
        #expect(model.chatGPTStatusTitle == L10n.string("Ready to open"))
        snapshot.chatGPTStatus = .connecting
        model.apply(snapshot)
        #expect(model.chatGPTBusy)
        #expect(!model.canDisconnectChatGPT)
        snapshot.chatGPTStatus = .needsAttention
        model.apply(snapshot)
        #expect(model.chatGPTStatusTitle == L10n.string("Needs attention"))
    }
}
