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
                "claude-fable-5",
                "claude-opus-5",
                "claude-sonnet-5",
                "claude-haiku-4-5-20251001",
            ])
    }
}
