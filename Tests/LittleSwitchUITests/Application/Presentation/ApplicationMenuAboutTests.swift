import AppKit
import LittleSwitchCore
import SwiftUI
import Testing

@testable import LittleSwitchUI

@Suite("Application About surface")
struct ApplicationMenuAboutTests {
    @Test("The app menu opens the same enlarged About window as the status menu")
    func aboutPanelCommand() throws {
        let menu = ApplicationMenuFactory.make()
        let appItem = try #require(menu.items.first { $0.title == "LittleSwitch" })
        let appSubmenu = try #require(appItem.submenu)
        let about = try #require(
            appSubmenu.items.first {
                $0.title == "About LittleSwitch"
            }
        )

        #expect(about.title == "About LittleSwitch")
        #expect(about.action == #selector(LittleSwitchApplicationDelegate.showAbout))
        #expect(about.target == nil)
        #expect(appSubmenu.title == "LittleSwitch")
    }

    @Test("The status menu opens the custom About window without adding separators")
    @MainActor
    func statusMenuAboutCommand() throws {
        let controller = try source(named: "MenuBar/StatusItemVisibilityRecovery.swift")
        let commands = StatusMenuCommands.makeItems(target: nil)
        let aboutItem = try #require(commands.first { $0.title == "About LittleSwitch" })
        let about = try source(named: "Application/Presentation/LittleSwitchApplicationDelegateAbout.swift")
        let window = try source(named: "Application/Presentation/AboutWindow.swift")

        #expect(aboutItem.action == #selector(LittleSwitchApplicationDelegate.showAbout))
        let separators = commands.filter(\.isSeparatorItem)
        #expect(separators.count == 1)
        #expect(commands.last?.title == "Quit LittleSwitch")
        #expect(!controller.contains("sectionHeader("))
        #expect(!controller.contains(".uppercased()"))
        // The tab switcher tops the menu.
        #expect(controller.contains("menu.addItem(switcher)"))
        #expect(about.contains("NSApplication.shared.activate(ignoringOtherApps: true)"))
        #expect(about.contains("window.makeKeyAndOrderFront(nil)"))
        #expect(!about.contains("orderFrontStandardAboutPanel"))
        #expect(window.contains("ApplicationBuild.currentTag"))
        #expect(
            window.contains("\"Copyright © 2026 LittleSwitch contributors\"")
        )
    }

    @Test("The delegate fronts one reusable custom About window")
    @MainActor
    func showAboutFrontsCustomWindow() throws {
        let delegate = LittleSwitchApplicationDelegate()
        delegate.showAbout()

        let window = try #require(LittleSwitchApplicationDelegate.aboutWindow)
        #expect(window.title == "About LittleSwitch")
        #expect(window.contentViewController is NSHostingController<AboutWindowContent>)
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.closable))
        #expect(!window.styleMask.contains(.resizable))
        #expect(!window.isReleasedWhenClosed)
        #expect(window.isVisible)

        delegate.showAbout()
        #expect(LittleSwitchApplicationDelegate.aboutWindow === window)

        LittleSwitchApplicationDelegate().showAbout()
        #expect(LittleSwitchApplicationDelegate.aboutWindow === window)
    }

    @Test("Fresh About windows are self-contained and non-resizable")
    @MainActor
    func makeAboutWindowBuildsIndependentPanel() {
        let window = LittleSwitchApplicationDelegate().makeAboutWindow()

        #expect(window.title == "About LittleSwitch")
        #expect(window.contentViewController != nil)
        #expect(!window.styleMask.contains(.resizable))
        #expect(!window.isReleasedWhenClosed)
        #expect(window !== LittleSwitchApplicationDelegate.aboutWindow)
    }

    @Test("The About copy shows the app name, build tag, and copyright")
    @MainActor
    func aboutWindowContentCopy() {
        let content = AboutWindowContent.current()

        #expect(content.displayName == "LittleSwitch")
        #expect(content.buildTag == ApplicationBuild.currentTag)
        #expect(
            AboutWindowContent.copyrightLine
                == "Copyright © 2026 LittleSwitch contributors"
        )
    }

    @Test("The About icon falls back to the status glyph without an app icon")
    @MainActor
    func aboutIconFallbackRenders() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(
            rootView: AboutWindowContent(
                displayName: "LittleSwitch",
                buildTag: "development",
                icon: nil
            )
        )
        window.makeKeyAndOrderFront(nil)

        #expect(window.isVisible)
    }

    private func source(named filename: String) throws -> String {
        let repository = RepositorySources.root
        return try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/LittleSwitchUI/\(filename)"
            ),
            encoding: .utf8
        )
    }
}
