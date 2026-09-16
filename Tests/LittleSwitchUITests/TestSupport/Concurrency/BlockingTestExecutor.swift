import Dispatch

/// Gives a deliberately blocking fixture its own thread source instead of
/// consuming a worker from Swift's bounded cooperative pool. Use a fresh
/// executor for each blocker so one held actor cannot stall another fixture.
@available(macOS 15.0, *)
final class BlockingTestExecutor: TaskExecutor {
    private let queue = DispatchQueue(label: "LittleSwitch.tests.blocking")

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let executor = asUnownedTaskExecutor()
        queue.async {
            job.runSynchronously(on: executor)
        }
    }
}
