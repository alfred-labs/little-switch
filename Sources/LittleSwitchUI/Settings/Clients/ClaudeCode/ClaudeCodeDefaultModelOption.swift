import LittleSwitchCommon

public struct ClaudeCodeDefaultModelOption: Equatable, Hashable, Identifiable, Sendable {
    public var routeID: String
    public var contextMode: ClaudeCodeContextMode
    public var label: String

    public var id: String {
        "\(routeID)|\(contextMode.rawValue)"
    }
}
