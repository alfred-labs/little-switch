import Testing

@testable import LittleSwitchUI

@Suite("Application relaunch recovery")
struct ApplicationRelaunchTests {
    @Test("A failed quit aborts the relaunch without opening")
    @MainActor
    func failedQuitAbortsRelaunch() async {
        let controller = TestClaudeController(running: true)
        controller.failNextQuit()

        #expect(await controller.relaunch() == .failed)
        #expect(controller.quitCount == 0)
        #expect(controller.openCount == 0)
    }

    @Test("A failed open still reports the relaunch attempt")
    @MainActor
    func failedOpenStillAttempts() async {
        let controller = TestClaudeController(running: true)
        controller.failNextOpen()

        #expect(await controller.relaunch() == .failed)
        #expect(controller.quitCount == 1)
        #expect(controller.openCount == 1)
    }

    @Test("A stopped application never relaunches")
    @MainActor
    func stoppedApplicationSkipsRelaunch() async {
        let controller = TestClaudeController(running: false)

        #expect(await controller.relaunch() == .notRunning)
        #expect(controller.quitCount == 0)
        #expect(controller.openCount == 0)
    }

    @Test("A running application comes back up")
    @MainActor
    func runningApplicationRelaunches() async {
        let controller = TestClaudeController(running: true)

        #expect(await controller.relaunch() == .relaunched)
        #expect(controller.quitCount == 1)
        #expect(controller.openCount == 1)
        #expect(controller.isRunning())
    }
}
