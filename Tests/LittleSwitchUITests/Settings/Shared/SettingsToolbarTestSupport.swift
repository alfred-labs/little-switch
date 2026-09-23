import AppKit

/// Native groups keep generated views on their subitems rather than on the
/// group itself. Inspect both forms through AppKit's public toolbar API.
@MainActor
enum SettingsToolbarTestSupport {
    static func items(in roots: [NSToolbarItem]) -> [NSToolbarItem] {
        roots.flatMap { item in
            [item] + items(in: (item as? NSToolbarItemGroup)?.subitems ?? [])
        }
    }

    static func views(in roots: [NSToolbarItem]) -> [NSView] {
        var visited = Set<ObjectIdentifier>()
        return items(in: roots).compactMap(\.view).filter { view in
            visited.insert(ObjectIdentifier(view)).inserted
        }
    }
}
