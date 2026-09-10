import AppKit
import LittleSwitchCore
import SwiftUI
import Testing

@testable import LittleSwitchUI

/// The status menu hosts SwiftUI through `NSMenuItem.view`. A hosted view
/// that has never been through a windowed display pass shows blank when
/// the menu opens: AppKit enters event tracking before SwiftUI's first
/// render, and the row only appears after the menu closes and reopens.
/// These tests pin the warmup contract that renders rows at creation, so
/// no opening is ever a row's first render — and that leaves them
/// detached, because the menu window only adopts rows without a
/// superview: a row kept in the warmup nursery is sized into the menu
/// layout but never shown in it.
@MainActor
@Suite("Status menu hosted view warmup")
struct StatusMenuHostedViewWarmupTests {
    /// Records whether SwiftUI actually displayed the probe: `onAppear`
    /// only fires once the content goes through a windowed render pass.
    private final class AppearanceProbe {
        var didAppear = false
    }

    private struct ProbeView: View {
        let probe: AppearanceProbe

        var body: some View {
            Text("probe")
                .frame(width: 100, height: 20)
                .onAppear {
                    probe.didAppear = true
                }
        }
    }

    @Test("A dashboard item view is rendered at creation and left detached")
    func dashboardHostingViewIsWarmAtCreation() throws {
        let item = NSMenuItem()

        GatewayActivityMenuItemRenderer.apply(
            Self.runningPresentation(runningCount: 1),
            to: item
        )

        let hosting = try #require(item.view)
        // Detached, not nursery-adopted: the menu window must be able to
        // take the row when it opens.
        #expect(hosting.window == nil)
    }

    @Test("Warmup renders a detached hosted view's SwiftUI content")
    func warmupRendersDetachedView() {
        let probe = AppearanceProbe()
        let view = NSHostingView(
            rootView: ProbeView(probe: probe).frame(width: 100, height: 20)
        )
        view.frame = NSRect(x: 0, y: 0, width: 100, height: 20)
        #expect(!probe.didAppear)

        StatusMenuHostedViewWarmup.warm(view: view)

        #expect(probe.didAppear)
        #expect(view.window == nil)
    }

    @Test("Warmup renders every menu item that hosts a view")
    func warmupRendersEveryHostedItem() {
        let probe = AppearanceProbe()
        let menu = NSMenu()
        let hosted = NSMenuItem()
        hosted.view = NSHostingView(
            rootView: ProbeView(probe: probe).frame(width: 100, height: 20)
        )
        menu.addItem(hosted)
        menu.addItem(NSMenuItem(title: "plain", action: nil, keyEquivalent: ""))

        StatusMenuHostedViewWarmup.warm(menu: menu)

        #expect(probe.didAppear)
        #expect(hosted.view?.window == nil)
    }

    @Test("Warmup is idempotent for an already-warmed view")
    func warmupIsIdempotentForWarmedView() throws {
        let probe = AppearanceProbe()
        let view = NSHostingView(
            rootView: ProbeView(probe: probe).frame(width: 100, height: 20)
        )
        StatusMenuHostedViewWarmup.warm(view: view)

        StatusMenuHostedViewWarmup.warm(view: view)

        #expect(probe.didAppear)
        #expect(view.window == nil)
    }

    @Test("Warmup does not steal a row held by a windowless item viewer")
    func warmupKeepsWindowlessViewerRowInPlace() throws {
        let probe = AppearanceProbe()
        let view = NSHostingView(
            rootView: ProbeView(probe: probe).frame(width: 100, height: 20)
        )
        StatusMenuHostedViewWarmup.warm(view: view)
        #expect(probe.didAppear)

        // Between openings the status menu keeps its item viewers alive:
        // the row has a superview whose window does not exist yet. Warmup
        // must complete the row's render in place, not adopt it into the
        // nursery — a stolen row leaves its viewer showing an empty slot
        // on every subsequent opening.
        let viewer = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        viewer.addSubview(view)

        StatusMenuHostedViewWarmup.warm(view: view)

        #expect(view.superview === viewer)
    }

    @Test("The menu delegate warms the menu it is about to open")
    func menuDelegateWarmsOnOpen() throws {
        let probe = AppearanceProbe()
        let menu = NSMenu()
        let hosted = NSMenuItem()
        hosted.view = NSHostingView(
            rootView: ProbeView(probe: probe).frame(width: 100, height: 20)
        )
        menu.addItem(hosted)

        let controller = StatusItemController(
            model: AppModel(),
            onToggleClaude: {},
            onToggleClaudeCode: {},
            onToggleCodex: {},
            onToggleOpenCode: {},
            onMapping: { _, _ in },
            onCodexDefault: { _ in },
            onCodexAutoReview: { _ in },
            onApplyClaude: { _, _ in },
            onApplyCodex: {}
        )
        controller.menuWillOpen(menu)

        #expect(probe.didAppear)
        #expect(hosted.view?.window == nil)
    }

    /// A running pool snapshot, the minimum presentation that renders the
    /// graphical dashboard.
    private static func runningPresentation(
        runningCount: Int
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
            ]
        )
    }
}
