enum StatusMenuCopy {
    /// Appended to an application row when that application holds settings the
    /// user has changed but not applied. The menu is where a disconnect or a
    /// quit is triggered, so it is where the warning has to be visible.
    static let pendingChanges = "Changes pending"

    static func customModelCount(_ count: Int) -> String {
        "\(count) custom \(count == 1 ? "model" : "models")"
    }

    static func detail(_ base: String, hasPendingChanges: Bool) -> String {
        hasPendingChanges ? "\(base) · \(pendingChanges)" : base
    }
}
