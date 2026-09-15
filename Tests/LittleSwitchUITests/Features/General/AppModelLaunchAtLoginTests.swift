import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("App model launch at login")
struct AppModelLaunchAtLoginTests {
    @Test("Launch at login exposes complete status, busy, and accessibility state")
    func presentation() {
        let model = AppModel()
        let expectations = [
            LaunchAtLoginPresentationExpectation(
                status: .disabled,
                enabled: false,
                canChange: true,
                requiresApproval: false,
                accessibilityValue: L10n.string("Launch at login disabled"),
                accessibilityHint: L10n.string("LittleSwitch does not open automatically")
            ),
            LaunchAtLoginPresentationExpectation(
                status: .enabled,
                enabled: true,
                canChange: true,
                requiresApproval: false,
                accessibilityValue: L10n.string("Launch at login enabled"),
                accessibilityHint: L10n.string("LittleSwitch opens in the menu bar when you log in")
            ),
            LaunchAtLoginPresentationExpectation(
                status: .requiresApproval,
                enabled: false,
                canChange: true,
                requiresApproval: true,
                accessibilityValue: L10n.string("Approval required"),
                accessibilityHint: L10n.string("Approve LittleSwitch in Login Items")
            ),
            LaunchAtLoginPresentationExpectation(
                status: .unavailable,
                enabled: false,
                // `.unavailable` maps SMAppService `.notFound`, which macOS
                // reports for never-registered apps; registering is still
                // possible, so the control must stay actionable.
                canChange: true,
                requiresApproval: false,
                accessibilityValue: L10n.string("Launch at login unavailable"),
                accessibilityHint: L10n.string("LittleSwitch is not registered with Login Items")
            ),
        ]

        for expectation in expectations {
            model.launchAtLoginStatus = expectation.status
            model.isChangingLaunchAtLogin = false
            #expect(model.launchAtLoginEnabled == expectation.enabled)
            #expect(model.canChangeLaunchAtLogin == expectation.canChange)
            #expect(model.launchAtLoginRequiresApproval == expectation.requiresApproval)
            #expect(model.launchAtLoginAccessibilityValue == expectation.accessibilityValue)
            #expect(model.launchAtLoginAccessibilityHint == expectation.accessibilityHint)
        }

        model.launchAtLoginStatus = .enabled
        model.isChangingLaunchAtLogin = true
        #expect(!model.canChangeLaunchAtLogin)
    }
}

private struct LaunchAtLoginPresentationExpectation {
    let status: LaunchAtLoginStatus
    let enabled: Bool
    let canChange: Bool
    let requiresApproval: Bool
    let accessibilityValue: String
    let accessibilityHint: String
}
