/// Process launch ownership is independent of saved connection intent. Startup
/// recovery cannot infer which environment an already-running desktop uses.
enum ChatGPTDesktopRestorationState: Equatable, Sendable {
    case unobserved
    case normal
    case managed
    /// A successfully closed desktop must reopen, even if shutdown supersedes
    /// the transaction that closed it before that transaction can launch it.
    case relaunchRequired

    var requiresRestoration: Bool {
        switch self {
        case .unobserved, .normal: false
        case .managed, .relaunchRequired: true
        }
    }
}
