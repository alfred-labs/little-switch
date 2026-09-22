import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Web search draft publication races")
struct WebSearchDraftPublicationRaceTests {
    private enum OperationError: Swift.Error { case injected }

    @Test(
        "An unrelated operation cannot replace an unpublished edit or clear", arguments: [false, true], [false, true])
    func unpublishedIntent(clearing: Bool, failing: Bool) async throws {
        let fixture = try await CodexCoverageFixture.make()
        let delegate = LittleSwitchApplicationDelegate()
        delegate.coordinator = fixture.coordinator
        let dirty = WebSearchPendingSettings(configuration: .init(provider: .firecrawl))
        delegate.model.apply(await fixture.coordinator.setWebSearchDraft(clearing ? dirty : nil))
        let gate = WebSearchPublicationGate()
        delegate.webSearchDraftTask = Task { await gate.wait() }
        let latest = clearing ? nil : dirty
        delegate.setWebSearchDraft(latest)

        let success = await delegate.perform { coordinator in
            if failing { throw OperationError.injected }
            return await coordinator.snapshot()
        }

        #expect(success == !failing)
        #expect(delegate.model.webSearchDraft == latest)
        await gate.open()
        await delegate.webSearchDraftTask?.value
        #expect((await fixture.coordinator.snapshot()).webSearchDraft == latest)
        #expect(delegate.model.webSearchDraft == latest)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("An old snapshot cannot replace a draft after publication completed", arguments: [false, true])
    func delayedSnapshot(clearing: Bool) async throws {
        let fixture = try await CodexCoverageFixture.make()
        let delegate = LittleSwitchApplicationDelegate()
        delegate.coordinator = fixture.coordinator
        let dirty = WebSearchPendingSettings(configuration: .init(provider: .firecrawl))
        let old = await fixture.coordinator.setWebSearchDraft(clearing ? dirty : nil)
        delegate.model.apply(old)
        let latest = clearing ? nil : dirty
        delegate.setWebSearchDraft(latest)
        await delegate.webSearchDraftTask?.value

        delegate.model.apply(old)

        #expect(delegate.model.webSearchDraft == latest)
        #expect((await fixture.coordinator.snapshot()).webSearchDraft == latest)
        await fixture.coordinator.shutdown(mode: .handoff)
    }

    @Test("An older publication cannot acknowledge a newer local intent")
    func olderAcknowledgment() async throws {
        let fixture = try await CodexCoverageFixture.make()
        let delegate = LittleSwitchApplicationDelegate()
        delegate.coordinator = fixture.coordinator
        delegate.model.apply(await fixture.coordinator.snapshot())
        delegate.setWebSearchDraft(nil)
        let first = try #require(delegate.webSearchDraftTask)
        let gate = WebSearchPublicationGate()
        delegate.webSearchDraftTask = Task {
            await first.value
            await gate.wait()
        }
        let latest = WebSearchPendingSettings(configuration: .init(provider: .firecrawl))
        delegate.setWebSearchDraft(latest)
        await first.value

        delegate.model.apply(await fixture.coordinator.snapshot())

        #expect(delegate.model.webSearchDraft == latest)
        await gate.open()
        await delegate.webSearchDraftTask?.value
        #expect(delegate.model.webSearchDraft == latest)
        await fixture.coordinator.shutdown(mode: .handoff)
    }
}

private actor WebSearchPublicationGate {
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}
