import Foundation
import LittleSwitchCore
import Testing

@testable import LittleSwitchUI

@Suite("Provider concurrency settings")
struct ProviderConcurrencySettingsTests {
    @Test("Provider inputs default and preserve parallel request settings")
    func providerInputMaximumParallelRequests() {
        let defaultInput = ProviderInput(
            name: "Default",
            baseURL: "https://example.com",
            authMode: .none
        )
        let explicitInput = ProviderInput(
            name: "Explicit",
            baseURL: "https://example.com",
            authMode: .none,
            maximumParallelRequests: 27
        )

        #expect(defaultInput.maximumParallelRequests == Provider.defaultMaximumParallelRequests)
        #expect(explicitInput.maximumParallelRequests == 27)
    }

    @Test("Invalid parallel request settings have actionable product copy")
    func invalidMaximumParallelRequestsDescription() {
        #expect(
            ApplicationCoordinator.Error.invalidMaximumParallelRequests.errorDescription
                == "Choose between 1 and 32 parallel requests."
        )
    }

    @Test("Provider editor uses the native bounded Stepper and shows its value")
    func providerEditorSource() throws {
        let source = try loadProviderEditorSource()
        let compactSource = source.filter { !$0.isWhitespace }

        #expect(
            compactSource.contains(
                #"Stepper(value:$draft.maximumParallelRequests,in:Provider.maximumParallelRequestsRange)"#
            )
        )
        #expect(compactSource.contains("Text(draft.maximumParallelRequests.formatted())"))
        #expect(compactSource.contains(".monospacedDigit()"))
        #expect(source.contains(#""Parallel requests""#))
        #expect(source.contains("Shared by every model and app using this provider."))
        #expect(source.contains("draft.apply(selection.providerPreset)"))
        var draft = ProviderDraft()
        draft.maximumParallelRequests = 27
        #expect(draft.makeInput().maximumParallelRequests == 27)
    }

    private func loadProviderEditorSource() throws -> String {
        let repository = RepositorySources.root
        return try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/LittleSwitchUI/Features/Providers/ProviderEditor.swift"
            ),
            encoding: .utf8
        )
    }
}
