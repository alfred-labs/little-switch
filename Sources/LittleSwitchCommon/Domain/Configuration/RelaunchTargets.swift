import Foundation

/// Products the user had connected when LittleSwitch last quit.
///
/// Quitting restores every managed profile so the gateway's address never
/// outlives the running app. This records the intent separately so the next
/// launch can put the switches back where the user left them.
public struct RelaunchTargets: Codable, Equatable, Sendable {
    public var claude: Bool
    public var codex: Bool
    public var claudeCode: Bool
    public var openCode: Bool

    public static let none = RelaunchTargets()

    public init(
        claude: Bool = false,
        codex: Bool = false,
        claudeCode: Bool = false,
        openCode: Bool = false
    ) {
        self.claude = claude
        self.codex = codex
        self.claudeCode = claudeCode
        self.openCode = openCode
    }

    public var isEmpty: Bool {
        !claude && !codex && !claudeCode && !openCode
    }
}
