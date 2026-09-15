import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchUI

@Suite("Provider editor save feedback")
struct ProviderEditorSaveFeedbackTests {
    @Test("A failed save outcome carries the message the editor shows")
    func failedOutcomeCarriesMessage() {
        let outcome = ProviderSaveOutcome.failed(
            "The credential script exited with status 127."
        )
        let message: String
        switch outcome {
        case .saved:
            message = ""
        case .failed(let text):
            message = text
        }
        #expect(message == "The credential script exited with status 127.")
    }

    @Test("Test outcomes separate the script stage from the endpoint probe")
    func outcomeStagesAreDistinct() {
        let scriptFailure = ProviderTestOutcome.scriptFailed("exited with status 3")
        let authFailure = ProviderTestOutcome.authenticationFailed("connection refused")
        let passed = ProviderTestOutcome.passed(scriptOutput: "Success! Logged in.")

        var scriptStage = false
        var authenticationStage = false
        var scriptOutput: String?
        switch scriptFailure {
        case .scriptFailed:
            scriptStage = true
        case .authenticationFailed, .passed:
            break
        }
        switch authFailure {
        case .authenticationFailed:
            authenticationStage = true
        case .scriptFailed, .passed:
            break
        }
        if case .passed(let output) = passed {
            scriptOutput = output
        }
        #expect(scriptStage)
        #expect(authenticationStage)
        #expect(scriptOutput == "Success! Logged in.")
    }

    @Test("The editor reports the two test stages with their own status")
    func editorShowsTwoTestStages() throws {
        let source = try loadSource("Settings/Providers/ProviderEditor.swift")

        #expect(source.contains("\"Test script valid\""))
        #expect(source.contains("\"Authentication successful\""))
        #expect(source.contains("ProviderEditorNotice.stageStatusRow("))
        #expect(source.contains("case .scriptFailed(let message):"))
        #expect(source.contains("case .authenticationFailed(let message):"))
        #expect(source.contains("exclamationmark.triangle.fill"))
    }

    @Test("Save unlocks only after a test passed and locks again on edits")
    func saveGatesOnTest() throws {
        let source = try loadSource("Settings/Providers/ProviderEditor.swift")

        #expect(source.contains("L10n.string(\"Testing…\")"))
        #expect(source.contains("L10n.string(\"Test Connection\")"))
        #expect(source.contains("L10n.string(\"Saving…\")"))
        #expect(source.contains("L10n.string(\"Save\")"))
        #expect(
            source.contains(".disabled(saving || testing || !testPassed || !formIsValid)")
        )
        #expect(source.contains(".onChange(of: draft.baseURL) { _, _ in"))
        // A new endpoint also retires the previous endpoint's route probe.
        #expect(source.contains("draft.wireProbe = nil"))
        #expect(source.contains(".onChange(of: draft.scriptPath) { _, _ in resetTestStages() }"))
    }

    @Test("The script is a chosen file path, not typed text")
    func scriptIsAFilePath() throws {
        let source = try loadSource("Settings/Providers/ProviderEditor.swift")

        #expect(source.contains(".fileImporter("))
        #expect(source.contains("draft.scriptPath = url.path"))
        #expect(!source.contains("TextEditor(text: $draft.scriptPath)"))
    }

    @Test("A running credential script says what the sheet is waiting on")
    func editorAnnouncesScriptRun() throws {
        let source = try loadSource("Settings/Providers/ProviderEditor.swift")

        #expect(source.contains("if (testing || saving) && draft.credentialSource == .script {"))
        #expect(
            source.contains(
                "Testing the credential script; it may open a browser or prompt to log in."
            )
        )
    }

    @Test("The delegate routes save errors back to the editor instead of the app alert")
    func delegateReturnsFailureToEditor() throws {
        let delegateSource = try loadSource("Application/Lifecycle/LittleSwitchApplicationDelegate.swift")
        let testSource = try loadSource("Features/Providers/LittleSwitchApplicationDelegateProviderTest.swift")

        #expect(testSource.contains("func testProvider(_ input: ProviderInput) async -> ProviderTestOutcome"))
        #expect(delegateSource.contains("async -> ProviderSaveOutcome"))
        #expect(delegateSource.contains("return .failed(startupErrorMessage(for: error))"))
        #expect(testSource.contains(".scriptFailed(startupErrorMessage(for: error))"))
        #expect(testSource.contains(".authenticationFailed(startupErrorMessage(for: error))"))
    }

    @Test("The settings view keeps the sheet open unless the save succeeded")
    func settingsViewClosesOnlyOnSuccess() throws {
        let source = try loadSource("Settings/Providers/ProvidersSettingsView.swift")

        #expect(source.contains("if case .saved = outcome {"))
    }

    private func loadSource(_ file: String) throws -> String {
        let repository = RepositorySources.root
        let files =
            file == "Settings/Providers/ProviderEditor.swift"
            ? [
                file, "Settings/Providers/ProviderEditorCredentials.swift",
                "Settings/Providers/ProviderEditorAdvanced.swift", "Settings/Providers/ProviderEditorNotice.swift",
            ]
            : [file]
        return
            try files
            .map { name in
                try String(
                    contentsOf: repository.appendingPathComponent("Sources/LittleSwitchUI/\(name)"),
                    encoding: .utf8
                )
            }
            .joined(separator: "\n")
    }
}
