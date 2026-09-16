import Testing

@testable import RepositoryTooling

@Suite("User-visible localization boundaries")
struct UserVisibleStringLocalizationTests {
    @Test("Localized values and technical helper arguments are not untranslated copy")
    func localizedValues() {
        let source = #"""
            Text(L10n.resource("Localized", comment: "Translator note"))
            Text(L10n.string("Localized string"))
            Text(String(localized: "Foundation value", table: "Technical table"))
            Text(LocalizedStringResource("Resource"))
            Text(LocalizedStringKey("Key"))
            Text(NSLocalizedString("Legacy key", comment: "Comment"))
            Text(flag ? L10n.resource("Localized branch") : "Raw fallback")
            Text(format(identifier: "technical identifier"))
            Text(["Opus", symbol].joined(separator: " "))
            alert.messageText = L10n.string("Localized alert")
            """#

        #expect(
            UserVisibleStringScanner.scan(source: source, filePath: "Copy.swift")
                == [
                    .init(
                        file: "Copy.swift",
                        line: 7,
                        column: 49,
                        api: "Text",
                        text: "Raw fallback",
                        staticSegments: ["Raw fallback"])
                ])
    }

    @Test("Native display APIs include sections, values, empty states and hints")
    func nativeDisplayAPIs() {
        let source = #"""
            Section("Credentials") {}
            LabeledContent("Status", value: "Disconnected")
            ContentUnavailableView("No models", systemImage: "tray", description: Text("Add a provider"))
            DisclosureGroup("Advanced") {}
            Text(verbatim: "Verbatim copy")
                .accessibilityHint("Open settings")
                .accessibilityValue("Disabled")
            SwiftUI.Text("Qualified text")
            """#

        let findings = UserVisibleStringScanner.scan(source: source, filePath: "Copy.swift")
        #expect(
            findings.map(\.text) == [
                "Credentials", "Status", "Disconnected", "No models", "Add a provider", "Advanced",
                "Open settings", "Disabled", "Qualified text",
            ])
        #expect(
            findings.map(\.api) == [
                "Section", "LabeledContent", "value", "ContentUnavailableView", "Text", "DisclosureGroup",
                "accessibilityHint", "accessibilityValue", "Text",
            ])
    }

    @Test("Verbatim text opts out explicitly without exempting adjacent display copy")
    func verbatimText() {
        let source = #"""
            Text(verbatim: "127.0.0.1:11436")
            SwiftUI.Text(verbatim: "Authorization: Bearer")
            Text(verbatim: "Version \(version)")
            TextField(L10n.string("Header"), text: $header, prompt: Text(verbatim: "X-Api-Key"))
            Text(verbatim: "X-Api-Key")
                .help("Visible help")
                .accessibilityLabel("Visible label")
            Text("X-Api-Key")
            Text("LittleSwitch")
            Text(ProductIdentity.displayName)
            window.title = ProductIdentity.displayName
            """#

        let findings = UserVisibleStringScanner.scan(source: source, filePath: "Copy.swift")
        #expect(findings.map(\.text) == ["Visible help", "Visible label", "X-Api-Key", "LittleSwitch"])
        #expect(findings.map(\.api) == ["help", "accessibilityLabel", "Text", "Text"])
    }

    @Test("Only returned text participates in conditionals, concatenation and nil coalescing")
    func displayedExpressions() {
        let source = #"""
            Text(mode == "technical-mode" ? "Visible" : L10n.string("Localized"))
            Text(optional ?? "Fallback")
            Text("Hello " + name + "!")
            Text(("Parenthesized"))
            Text("Casted" as String)
            NSMenuItem(title: flag ? "First" : "Second", action: nil, keyEquivalent: "x")
            """#

        #expect(
            UserVisibleStringScanner.scan(source: source, filePath: "Copy.swift").map(\.text)
                == ["Visible", "Fallback", "Hello ", "!", "Parenthesized", "Casted", "First", "Second"])
    }

    @Test("Non-display expressions do not turn operands or tuple fields into copy")
    func nonDisplayExpressions() {
        let source = #"""
            Text(value == "technical-state")
            Text(value = "stored-value")
            Text(("tuple-field", value))
            Text((label: "metadata"))
            """#
        #expect(UserVisibleStringScanner.scan(source: source, filePath: "Copy.swift").isEmpty)
    }

    @Test("Nested presentation calls report each literal once and ignore unrelated labels")
    func displayPositions() {
        let source = #"""
            TextField("Address", text: $address, prompt: Text("Example"))
            SettingsSection("Network", subtitle: L10n.string("Localized subtitle")) {}
            request(prompt: "model prompt", detail: "technical detail", subtitle: "metadata")
            Text(value).help(Text("Help", tableName: "Technical table"))
            """#

        let findings = UserVisibleStringScanner.scan(source: source, filePath: "Copy.swift")
        #expect(findings.map(\.text) == ["Address", "Example", "Network", "Help"])
        #expect(findings.map(\.api) == ["TextField", "Text", "SettingsSection", "Text"])
    }

    @Test("Raw interpolation keeps its contents without exposing quote delimiters")
    func rawInterpolation() {
        let source = ##"Text(#"Version \#(version)"#)"##
        #expect(
            UserVisibleStringScanner.scan(source: source, filePath: "Copy.swift")
                == [
                    .init(
                        file: "Copy.swift",
                        line: 1,
                        column: 6,
                        api: "Text",
                        text: ##"Version \#(version)"##,
                        staticSegments: ["Version "])
                ])
    }
}
