import AppKit

extension LittleSwitchApplicationDelegate {
    /// Retains the single About window so repeat menu picks reuse it
    /// instead of stacking panels. Extensions cannot add stored instance
    /// properties, so the process-wide reference lives on the type.
    static var aboutWindow: NSWindow?

    @objc func showAbout() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let window = Self.aboutWindow ?? makeAboutWindow()
        Self.aboutWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    func makeAboutWindow() -> NSWindow {
        AboutWindowFactory.makeWindow()
    }
}
