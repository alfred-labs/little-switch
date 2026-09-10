import AppKit
import Testing

@testable import LittleSwitchUI

@MainActor
@Suite("Status menu Settings presentation")
struct StatusMenuSettingsPresentationTests {
    @Test("The gear activates during the click and presents Settings after menu tracking", .timeLimit(.minutes(1)))
    func waitsForMenuTrackingToEnd() async {
        _ = NSApplication.shared
        let result = await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.default]) {
                MainActor.assumeIsolated {
                    var activationModes: [RunLoop.Mode?] = []
                    var presentationModes: [RunLoop.Mode?] = []
                    let controller = StatusItemController(
                        model: AppModel(),
                        onToggleClaude: {},
                        onToggleClaudeCode: {},
                        onToggleCodex: {},
                        onToggleOpenCode: {},
                        onMapping: { _, _ in },
                        onCodexDefault: { _ in },
                        onCodexAutoReview: { _ in },
                        onApplyClaude: { _, _ in },
                        onApplyCodex: {},
                        onShowSettings: { presentationModes.append(RunLoop.main.currentMode) }
                    )
                    RunLoop.main.perform(inModes: [.eventTracking]) {
                        MainActor.assumeIsolated {
                            controller.showSettings {
                                activationModes.append(RunLoop.main.currentMode)
                            }
                        }
                    }
                    let trackingDeadline = Date().addingTimeInterval(0.05)
                    while Date() < trackingDeadline {
                        RunLoop.main.run(mode: .eventTracking, before: trackingDeadline)
                    }
                    let duringTracking = presentationModes
                    let presentationDeadline = Date().addingTimeInterval(0.05)
                    while presentationModes.isEmpty && Date() < presentationDeadline {
                        RunLoop.main.run(mode: .default, before: presentationDeadline)
                    }
                    continuation.resume(returning: (activationModes, duringTracking, presentationModes))
                }
            }
        }

        #expect(result.0 == [.eventTracking])
        #expect(result.1.isEmpty)
        #expect(result.2 == [.default])
    }
}
