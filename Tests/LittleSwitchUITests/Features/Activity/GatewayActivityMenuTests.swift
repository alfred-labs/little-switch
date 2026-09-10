import AppKit
import LittleSwitchCore
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Gateway activity menu")
struct GatewayActivityMenuTests {
    /// A running pool snapshot paired with its presentation.
    private static func runningPresentation(
        runningCount: Int,
        usage: GatewayUsageSummary? = nil
    ) -> GatewayActivityPresentation {
        let providerID = UUID()
        return GatewayActivityPresentation(
            activity: .running(
                ProviderRequestPoolSnapshot(
                    totalRunning: runningCount,
                    totalWaiting: 0,
                    providers: [
                        ProviderRequestPoolProviderSnapshot(
                            id: providerID,
                            displayName: "z.ai",
                            maximumParallelRequests: 4,
                            runningCount: runningCount,
                            waitingCount: 0,
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
            ],
            usage: usage
        )
    }

    @Test("Active activity renders the dashboard view instead of a title")
    func dashboardRendering() throws {
        let item = NSMenuItem()
        item.title = "stale"
        item.attributedTitle = NSAttributedString(string: "stale")

        GatewayActivityMenuItemRenderer.apply(Self.runningPresentation(runningCount: 1), to: item)

        #expect(item.view is NSHostingView<GatewayActivityDashboardView>)
        #expect(item.attributedTitle == nil)
        #expect(item.image == nil)

        #expect(GatewayActivityDashboardView.height(stats: nil) > 0)
    }

    /// Polling applies a fresh dashboard twice a second. The hosting view must
    /// survive those ticks with its data refreshed in place: swapping the view
    /// while the menu tracks steals the highlight from the rows below.
    @Test("Same-geometry updates refresh the view in place")
    func inPlaceUpdate() throws {
        let item = NSMenuItem()
        GatewayActivityMenuItemRenderer.apply(Self.runningPresentation(runningCount: 1), to: item)
        let first = try #require(item.view as? NSHostingView<GatewayActivityDashboardView>)

        GatewayActivityMenuItemRenderer.apply(Self.runningPresentation(runningCount: 5), to: item)

        #expect(item.view === first)
        #expect(first.rootView.runningCount == 5)

        GatewayActivityMenuItemRenderer.apply(
            Self.runningPresentation(runningCount: 2), to: item
        )
        #expect(item.view === first)
        #expect(first.rootView.runningCount == 2)
    }

    @Test("A geometry change rebuilds the hosted view so the menu remeasures")
    func geometryChangeRebuilds() throws {
        let item = NSMenuItem()
        GatewayActivityMenuItemRenderer.apply(Self.runningPresentation(runningCount: 1), to: item)
        let first = try #require(item.view)

        GatewayActivityMenuItemRenderer.apply(
            Self.runningPresentation(
                runningCount: 1,
                usage: GatewayUsageSummary(history: GatewayUsageHistory(), now: Date())
            ),
            to: item
        )

        #expect(item.view !== first)
        #expect(item.view is NSHostingView<GatewayActivityDashboardView>)
    }

    @Test("An active pool snapshot renders without usage history")
    func dashboardWithoutUsage() {
        let item = NSMenuItem()
        GatewayActivityMenuItemRenderer.apply(Self.runningPresentation(runningCount: 1), to: item)

        #expect(item.view != nil)
        #expect(item.attributedTitle == nil)
    }

    @Test("Textual states keep the attributed title and clear any dashboard view")
    func textualRendering() throws {
        let provider = Provider(
            name: "Provider",
            baseURL: "https://example.com",
            authMode: .none
        )
        let cases = [
            (
                GatewayActivityPresentation(
                    activity: .starting,
                    providers: [provider]
                ),
                "Starting gateway…"
            ),
            (
                GatewayActivityPresentation(
                    activity: .unavailable,
                    providers: [provider]
                ),
                "Gateway unavailable"
            ),
        ]
        for (presentation, expectedTitle) in cases {
            let item = NSMenuItem(title: "stale", action: nil, keyEquivalent: "x")
            item.view = NSView()

            GatewayActivityMenuItemRenderer.apply(presentation, to: item)

            #expect(item.view == nil)
            #expect(item.title == expectedTitle)
            #expect(item.image?.accessibilityDescription == "Gateway activity")
            #expect(item.accessibilityLabel() == presentation.menu.accessibilityLabel)
            #expect(item.accessibilityValue() as? String == presentation.menu.accessibilityValue)
            #expect(item.accessibilityHelp() == presentation.menu.accessibilityHint)
            let attributedTitle = try #require(item.attributedTitle)
            let font = try #require(
                attributedTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            )
            let expectedFont = NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize,
                weight: .regular
            )
            #expect(font.fontName == expectedFont.fontName)
            #expect(font.pointSize == expectedFont.pointSize)
        }
    }

    @Test("Idle with configured providers still charts the empty dashboard")
    func idleRendersEmptyDashboard() {
        let provider = Provider(
            id: UUID(),
            name: "z.ai",
            baseURL: "https://example.com",
            authMode: .none,
            models: []
        )
        let presentation = GatewayActivityPresentation(
            activity: .running(
                ProviderRequestPoolSnapshot(
                    totalRunning: 0,
                    totalWaiting: 0,
                    providers: []
                )
            ),
            providers: [provider]
        )
        let item = NSMenuItem(title: "stale", action: nil, keyEquivalent: "x")

        GatewayActivityMenuItemRenderer.apply(presentation, to: item)

        #expect(item.view != nil)
        #expect(item.attributedTitle == nil)
        #expect(presentation.menu.dashboard == .init(runningCount: 0, waitingCount: 0, stats: nil))
    }

    @Test("A section separator precedes display-only activity above the footer")
    func nativePlacementAndAction() throws {
        let source = try uiSource(named: "MenuBar/StatusItemVisibilityRecovery.swift")
        let hostingItem = try #require(source.range(of: "menu.addItem(status)"))
        let activityItem = try #require(
            source.range(
                of: "let gatewayActivityItem",
                range: hostingItem.upperBound..<source.endIndex
            )
        )
        let activityAdded = try #require(
            source.range(
                of: "menu.addItem(gatewayActivityItem)",
                range: activityItem.upperBound..<source.endIndex
            )
        )
        let commands = try #require(
            source.range(
                of: "StatusMenuCommands.makeItems(target: delegate)",
                range: activityAdded.upperBound..<source.endIndex
            )
        )

        #expect(hostingItem.lowerBound < activityItem.lowerBound)
        #expect(activityAdded.lowerBound < commands.lowerBound)
        let sectionBoundary = String(source[hostingItem.upperBound..<activityItem.lowerBound])
        #expect(sectionBoundary.contains("NSMenuItem.separator()"))
        #expect(source.contains("overview: [status, activitySeparator, gatewayActivityItem]"))
        // Display-only: no action, so the row can never present as clickable.
        let itemConstruction = String(source[activityItem.lowerBound..<activityAdded.lowerBound])
        #expect(itemConstruction.contains("action: nil"))
        // The poll must not touch an unchanged menu, and a rebuilt menu must
        // render once even when the presentation did not move.
        #expect(source.contains("presentation != lastRenderedGatewayActivity"))
        #expect(source.contains("lastRenderedGatewayActivity = nil"))
        #expect(source.contains("refreshGatewayActivity()"))
        #expect(!source.contains("NSAccessibility.post"))
    }

    private func uiSource(named filename: String) throws -> String {
        let repository = RepositorySources.root
        return try String(
            contentsOf: repository.appendingPathComponent(
                "Sources/LittleSwitchUI/\(filename)"
            ),
            encoding: .utf8
        )
    }
}
