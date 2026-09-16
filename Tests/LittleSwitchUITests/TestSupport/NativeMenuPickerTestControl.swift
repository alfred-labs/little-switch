import AppKit
import Testing

/// Exercises a hosted menu picker's public AppKit menu contract without
/// assuming SwiftUI uses NSPopUpButton or opening a modal menu tracking loop.
@MainActor
struct NativeMenuPickerTestControl {
    let root: NSView
    let identifyingTitle: String

    var nativeView: NSView {
        get throws { try match.view }
    }

    var titles: [String] {
        get throws { try match.menu.items.map(\.title) }
    }

    var selectedTitle: String {
        get throws {
            let selected = try match.menu.items.filter { $0.state == .on }
            try #require(selected.count == 1, "A menu picker must have exactly one selected item.")
            return selected[0].title
        }
    }

    func select(_ title: String) throws {
        let menu = try match.menu
        let index = menu.indexOfItem(withTitle: title)
        try #require(index >= 0, "Missing menu item \(title); available: \(menu.items.map(\.title))")
        menu.performActionForItem(at: index)
    }

    private var match: (view: NSView, menu: NSMenu) {
        get throws {
            let views = descendants(root)
            var candidates: [ObjectIdentifier: (view: NSView, menu: NSMenu)] = [:]
            for view in views {
                for menu in [view.menu, (view as? NSControl)?.cell?.menu].compactMap(\.self)
                where menu.items.contains(where: { $0.title == identifyingTitle }) {
                    candidates[ObjectIdentifier(menu)] = (view, menu)
                }
            }
            let viewTypes = views.map { String(describing: type(of: $0)) }
            try #require(
                candidates.count == 1,
                "Expected one menu containing \(identifyingTitle), found \(candidates.count); views: \(viewTypes)"
            )
            return try #require(candidates.values.first)
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
}
