import Testing

@testable import LittleSwitchCommon

@Suite("Claude route identities")
struct ClaudeRouteTests {
    @Test("The four Claude routes keep their public order and identifiers")
    func fixedRoutes() {
        #expect(
            ClaudeRoute.all.map(\.displayName) == [
                "Fable", "Opus", "Sonnet", "Haiku",
            ])
        #expect(
            ClaudeRoute.all.map(\.id) == [
                "claude-fable-5-1",
                "claude-opus-5",
                "claude-sonnet-5",
                "claude-haiku-4-5-20251001",
            ])
    }

    @Test("A private route keeps its own label when presented as a family choice")
    func privateRouteLabel() {
        let route = ClaudeRoute(
            id: "private-route",
            displayName: "Private model",
            family: "sonnet",
            createdAt: "2026-09-16T00:00:00Z",
            isFamilyDefault: true
        )
        let choice = ClaudeCodeModelChoice(route: route, supports1MContext: true, indicator: .none)
        #expect(choice.id == "sonnet")
        #expect(choice.reference == "private-route[1m]")
        #expect(choice.label == "Private model (1M context)")
    }
}
