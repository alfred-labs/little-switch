import AppKit
import Observation

/// AppKit handles custom menu-item views' key equivalents during tracking;
/// the menuHasKeyEquivalent delegate hook only runs outside that loop.
@MainActor
final class MenuApplyMenuItem: NSMenuItem {
    private let applyAction: MenuApplyAction
    private var isTracking = false
    private var availabilityObserver: MenuApplyAvailabilityObserver?

    init(applyAction: MenuApplyAction) {
        self.applyAction = applyAction
        super.init(title: "", action: #selector(performApply), keyEquivalent: "")
        target = self
        keyEquivalentModifierMask = []
        availabilityObserver = MenuApplyAvailabilityObserver(item: self)
        availabilityObserver?.start()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("MenuApplyMenuItem is created programmatically")
    }

    func setTabVisible(_ visible: Bool) {
        isHidden = !visible
        updateShortcut()
    }

    func setTracking(_ isTracking: Bool) {
        self.isTracking = isTracking
        updateShortcut()
    }

    fileprivate func updateShortcut() {
        let canApply = applyAction.isEnabled
        // Keep the hosted mappings usable when Apply is disabled. Only
        // the key equivalent and the SwiftUI button follow Apply's gate.
        keyEquivalent = isTracking && !isHidden && canApply ? "\r" : ""
    }

    @objc private func performApply() {
        // Native menu activation may close tracking before the callback.
        // The action rechecks the live busy/pending state before dispatch.
        if !isHidden {
            applyAction()
        }
    }
}

/// Keep AppKit's non-Sendable menu item on the main actor. Observation's
/// Sendable callback captures this actor-isolated owner, not the NSMenuItem.
@MainActor
private final class MenuApplyAvailabilityObserver {
    private weak var item: MenuApplyMenuItem?

    init(item: MenuApplyMenuItem) {
        self.item = item
    }

    func start() {
        withObservationTracking {
            item?.updateShortcut()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.start()
            }
        }
    }
}
