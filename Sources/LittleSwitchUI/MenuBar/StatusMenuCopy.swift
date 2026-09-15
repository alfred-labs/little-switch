enum StatusMenuCopy {
    /// Appended to an application row when that application holds settings the
    /// user has changed but not applied. The menu is where a disconnect or a
    /// quit is triggered, so it is where the warning has to be visible.
    static var pendingChanges: String {
        L10n.string("Changes pending")
    }

    static func customModelCount(_ count: Int) -> String {
        count == 1
            ? L10n.string("\(count) custom model")
            : L10n.string("\(count) custom models")
    }

    static func detail(_ base: String, hasPendingChanges: Bool) -> String {
        hasPendingChanges ? L10n.string("\(base) · \(pendingChanges)") : base
    }
}
