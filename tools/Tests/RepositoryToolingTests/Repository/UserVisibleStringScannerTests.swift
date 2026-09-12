import Foundation
import Testing

@testable import RepositoryTooling

@Test("User-visible string scanner detects display entry points")
func userVisibleStringScannerDetectsDisplayEntryPoints() {
    let source = """
        import SwiftUI

        func display(value: String, flag: Bool) {
            Text("Settings")
            Label("Apply changes", systemImage: "checkmark.circle")
            Button("Save") {}
            TextField("API key", text: .constant(""))
            SecureField("Token", text: .constant(""))
            Toggle("Use LittleSwitch", isOn: .constant(false))
                .help("Apply changes")
                .accessibilityLabel("Settings")
                .navigationTitle("Providers")
                .alert("Export failed", isPresented: .constant(false)) {}
                .confirmationDialog("Discard changes?", isPresented: .constant(false)) {}
            let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
            let alert = NSAlert()
            alert.addButton(withTitle: "Cancel")
            alert.messageText = "LittleSwitch"
            alert.informativeText = "The gateway could not start."
        }
        """

    let findings = UserVisibleStringScanner.scan(source: source, filePath: "Presentation.swift")

    #expect(
        findings.map(\.api) == [
            "Text",
            "Label",
            "Button",
            "TextField",
            "SecureField",
            "Toggle",
            "help",
            "accessibilityLabel",
            "navigationTitle",
            "alert",
            "confirmationDialog",
            "NSMenuItem(title:)",
            "addButton(withTitle:)",
            "messageText",
            "informativeText",
        ])
    #expect(
        findings.map(\.text) == [
            "Settings",
            "Apply changes",
            "Save",
            "API key",
            "Token",
            "Use LittleSwitch",
            "Apply changes",
            "Settings",
            "Providers",
            "Export failed",
            "Discard changes?",
            "Edit",
            "Cancel",
            "LittleSwitch",
            "The gateway could not start.",
        ])
    #expect(findings.allSatisfy { $0.file == "Presentation.swift" })
    #expect(findings.allSatisfy { $0.line > 0 && $0.column > 0 })
}

@Test("User-visible string scanner ignores technical strings and variables")
func userVisibleStringScannerIgnoresTechnicalStringsAndVariables() {
    let source = """
        import SwiftUI

        func display(value: String) {
            Text(value)
            Label(value, systemImage: "checkmark.circle")
            Image(systemName: "gear")
            Button(action: {}) { Text(value) }
            TextField(text: .constant(value)) { Text(value) }
            let item = NSMenuItem(title: value, action: nil, keyEquivalent: "")
        }
        """

    let findings = UserVisibleStringScanner.scan(source: source, filePath: "Presentation.swift")

    #expect(findings.isEmpty)
}

@Test("User-visible string scanner finds literals nested in ternaries")
func userVisibleStringScannerFindsTernaryLiterals() {
    let source = """
        import SwiftUI

        func display(flag: Bool) {
            Text(flag ? "Connected" : "Not connected")
            Button(flag ? "Apply" : "Applying…") {}
                .help(flag ? "Hide sidebar" : "Show sidebar")
            let alert = NSAlert()
            alert.messageText = flag ? "Title" : "Fallback"
        }
        """

    let findings = UserVisibleStringScanner.scan(source: source, filePath: "Presentation.swift")

    #expect(
        findings.map(\.text) == [
            "Connected", "Not connected", "Apply", "Applying…", "Hide sidebar", "Show sidebar",
            "Title", "Fallback",
        ])
}

@Test("User-visible string scanner covers pickers, sections, steppers and AppKit titles")
func userVisibleStringScannerCoversAdditionalAPIs() {
    let source = """
        import SwiftUI
        import AppKit

        func display() {
            Picker("Metrics interval", selection: .constant(0)) {}
            ProgressView("Loading…")
            Stepper("Value", value: .constant(0), in: 0...1)
            GroupBox("Network") {}
            Menu("Actions") {}
            SettingsSection("Startup") {}
            let menu = NSMenu(title: "Edit")
            let window = NSWindow()
            window.title = "LittleSwitch"
            let item = NSMenuItem()
            item.title = "Copy"
        }
        """

    let findings = UserVisibleStringScanner.scan(source: source, filePath: "Presentation.swift")

    #expect(
        findings.map(\.text) == [
            "Metrics interval", "Loading…", "Value", "Network", "Actions", "Startup", "Edit",
            "LittleSwitch", "Copy",
        ])
}

@Test("User-visible string scanner reports static segments of interpolated literals")
func userVisibleStringScannerReportsInterpolatedSegments() {
    let source = """
        import SwiftUI

        func display(tag: String) {
            Text("Version \\(tag)")
        }
        """

    let findings = UserVisibleStringScanner.scan(source: source, filePath: "Presentation.swift")

    #expect(findings.map(\.text) == ["Version \\(tag)"])
    #expect(findings.map(\.staticSegments) == [["Version "]])
}

@Test("User-visible string scanner covers labeled arguments and AppKit initializers")
func userVisibleStringScannerCoversLabeledArgumentsAndAppKit() {
    let source = """
        import SwiftUI
        import AppKit

        func display() {
            SettingsSection("Model routing", subtitle: "For Codex Desktop and CLI.") {}
            SettingsSectionHeader("Settings", subtitle: "All providers.")
            TextField("Receiver URL", text: .constant(""), prompt: Text("https://localhost"))
            let menu = NSMenu(title: "Edit")
            let status = NSStatusItem(length: 24)
            let window = NSWindow(title: "About", styleMask: [.titled], backing: .buffered, defer: false)
        }
        """

    let findings = UserVisibleStringScanner.scan(source: source, filePath: "Presentation.swift")

    #expect(
        findings.map(\.text) == [
            "Model routing", "For Codex Desktop and CLI.", "Settings", "All providers.",
            "https://localhost", "Receiver URL", "https://localhost", "Edit", "About",
        ])
}

@Test("User-visible string scanner excludes empty separator titles")
func userVisibleStringScannerExcludesEmptySeparators() {
    let source = """
        import AppKit

        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let alert = NSAlert()
        alert.addButton(withTitle: "")
        """

    let findings = UserVisibleStringScanner.scan(source: source, filePath: "Separator.swift")

    #expect(findings.isEmpty)
}
