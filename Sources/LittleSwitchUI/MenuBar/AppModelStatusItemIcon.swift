extension AppModel {
    /// The menu-bar mark reports one thing: whether anything routes through
    /// LittleSwitch right now. It reads the same four switches the status menu
    /// shows, so the glyph can never disagree with the rows below it.
    var statusItemIconState: StatusItemIconState {
        let switchedOn =
            connected
            || claudeCodeSwitchOn
            || codexConnected
            || openCodeSwitchOn
        return switchedOn ? .active : .idle
    }
}
