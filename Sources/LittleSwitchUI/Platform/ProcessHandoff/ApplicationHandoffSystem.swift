import AppKit
import Darwin
import Foundation
import LittleSwitchCore

package struct NSWorkspaceApplicationProcessDiscovery: ApplicationProcessDiscovering {
    private let bundleIdentifier: String

    package init(bundleIdentifier: String = ProductIdentity.bundleIdentifier) {
        self.bundleIdentifier = bundleIdentifier
    }

    package func instances() async -> [ApplicationProcessIdentity] {
        await MainActor.run {
            NSWorkspace.shared.runningApplications.compactMap { application in
                guard application.bundleIdentifier == bundleIdentifier,
                    let launchDate = application.launchDate
                else {
                    return nil
                }
                return ApplicationProcessIdentity(
                    processIdentifier: application.processIdentifier,
                    launchDate: launchDate
                )
            }
        }
    }
}

extension POSIXApplicationProcessSignaler {
    package init() {
        self.init(
            identityForPID: { processIdentifier in
                await MainActor.run {
                    guard
                        let application = NSRunningApplication(
                            processIdentifier: processIdentifier
                        ),
                        application.bundleIdentifier == ProductIdentity.bundleIdentifier,
                        let launchDate = application.launchDate
                    else {
                        return nil
                    }
                    return ApplicationProcessIdentity(
                        processIdentifier: processIdentifier,
                        launchDate: launchDate
                    )
                }
            },
            sendSignal: { processIdentifier, signal in
                Darwin.kill(processIdentifier, signal)
            }
        )
    }
}

package struct ContinuousApplicationHandoffTiming: ApplicationHandoffTiming {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    package init() {
        origin = clock.now
    }

    package func now() async -> Duration {
        origin.duration(to: clock.now)
    }

    package func sleep(for duration: Duration) async throws {
        try await clock.sleep(for: duration)
    }
}

@MainActor
package final class ApplicationHandoffSignalMonitor {
    private var source: DispatchSourceSignal?

    package init() {}

    package func start(
        onHandoff: @escaping @MainActor @Sendable () -> Void
    ) {
        guard source == nil else {
            return
        }
        Darwin.signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler {
            Task { @MainActor in
                onHandoff()
            }
        }
        source.resume()
        self.source = source
    }

    package func stop() {
        source?.cancel()
        source = nil
    }
}
