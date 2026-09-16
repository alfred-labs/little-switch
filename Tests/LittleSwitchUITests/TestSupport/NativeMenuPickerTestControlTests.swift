import AppKit
import Testing

@MainActor
@Suite("Native menu picker test control")
struct NativeMenuPickerTestControlTests {
    @Test("Menus are exercised without depending on a popup button class", arguments: MenuLocation.allCases)
    func publicMenuContract(location: MenuLocation) throws {
        let target = SelectionTarget()
        let menu = NSMenu()
        menu.autoenablesItems = false
        for title in ["First", "Second"] {
            let item = NSMenuItem(title: title, action: #selector(SelectionTarget.select(_:)), keyEquivalent: "")
            item.target = target
            menu.addItem(item)
        }
        menu.items[0].state = .on
        let control = NSControl()
        control.cell = NSCell()
        if location != .cell { control.menu = menu }
        if location != .view { control.cell?.menu = menu }
        let root = NSView()
        root.addSubview(control)
        let picker = NativeMenuPickerTestControl(root: root, identifyingTitle: "Second")

        #expect(try picker.nativeView === control)
        #expect(try picker.titles == ["First", "Second"])
        #expect(try picker.selectedTitle == "First")
        try picker.select("Second")
        #expect(target.selections == ["Second"])
        #expect(try picker.selectedTitle == "Second")
    }

    enum MenuLocation: CaseIterable, Sendable {
        case view, cell, both
    }

    private final class SelectionTarget: NSObject {
        var selections: [String] = []

        @objc func select(_ item: NSMenuItem) {
            selections.append(item.title)
            for candidate in item.menu?.items ?? [] {
                candidate.state = candidate === item ? .on : .off
            }
        }
    }
}
