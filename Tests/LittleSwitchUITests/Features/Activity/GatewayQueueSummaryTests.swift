import AppKit
import SwiftUI
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Gateway queue summary")
struct GatewayQueueSummaryTests {
    @Test("Live queue values remain display-only and fit at the menu width")
    func countsAndLayout() async throws {
        for count in [0, 3, 9_999] {
            let content = GatewayQueueSummaryView(runningCount: count, waitingCount: count)
            let host = MenuControlTestHost(content, width: 296, height: 32)
            defer { host.close() }
            try await host.activateAccessibility()

            let queue = try host.element(label: "Request queue")
            let formatted = count.formatted(.number)
            #expect(queue.accessibilityValueDescription() == "\(formatted) running, \(formatted) pending")
            #expect(queue.accessibilityRole() != .button)
            #expect(host.hosting.fittingSize.height == 32)
            #expect(host.hosting.fittingSize.width <= 296)
        }
    }
}
