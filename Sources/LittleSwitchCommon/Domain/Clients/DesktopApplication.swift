public enum DesktopApplication: CaseIterable, Hashable, Sendable {
    case claude
    case codex
    case openCode
}

public enum DesktopApplicationAccess: Equatable, Sendable {
    case available
    case notInstalled
    case organizationManaged
}

public struct DesktopApplicationAvailability: Equatable, Sendable {
    public var claude: DesktopApplicationAccess
    public var codex: DesktopApplicationAccess
    public var openCode: DesktopApplicationAccess

    public init(
        claude: DesktopApplicationAccess = .notInstalled,
        codex: DesktopApplicationAccess = .notInstalled,
        openCode: DesktopApplicationAccess = .notInstalled
    ) {
        self.claude = claude
        self.codex = codex
        self.openCode = openCode
    }

    public subscript(application: DesktopApplication) -> DesktopApplicationAccess {
        switch application {
        case .claude: claude
        case .codex: codex
        case .openCode: openCode
        }
    }
}
