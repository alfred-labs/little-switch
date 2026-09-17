import AppKit
import Darwin
import Foundation
import os

private typealias TestingEntryPoint =
    @convention(thin) @Sendable (
        UnsafeRawBufferPointer?,
        @escaping @Sendable (UnsafeRawBufferPointer) -> Void
    ) async throws -> Bool

private enum TestHostError: Error {
    case missingTestExecutable
    case missingTestBundle(path: String)
    case missingTestingEntryPoint
}

@MainActor
private final class TestHostDelegate: NSObject, NSApplicationDelegate {
    private var didStart = false
    private var hostWindow: NSWindow?
    private let previousApplication = NSWorkspace.shared.frontmostApplication
    private let activatesApplication: Bool

    init(activatesApplication: Bool) {
        self.activatesApplication = activatesApplication
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        Task { await run() }
    }

    private func run() async {
        do {
            if activatesApplication {
                activateApplication()
            }
            let environment = ProcessInfo.processInfo.environment
            guard let executablePath = environment["LITTLESWITCH_SWIFT_TEST_EXECUTABLE"] else {
                throw TestHostError.missingTestExecutable
            }
            let executable = URL(fileURLWithPath: executablePath)
            let bundleURL =
                executable
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            guard let bundle = Bundle(path: bundleURL.path) else {
                throw TestHostError.missingTestBundle(path: bundleURL.path)
            }
            try bundle.loadAndReturnError()
            guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swt_abiv0_getEntryPoint") else {
                throw TestHostError.missingTestingEntryPoint
            }
            let getter = unsafeBitCast(symbol, to: (@convention(c) () -> UnsafeRawPointer).self)
            let entry = unsafeBitCast(getter(), to: TestingEntryPoint.self)
            let discoveredTests = OSAllocatedUnfairLock(initialState: 0)

            let passed = try await entry(nil) { record in
                guard let baseAddress = record.baseAddress else { return }
                let data = Data(bytes: baseAddress, count: record.count)
                guard let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                    record["kind"] as? String == "test"
                else {
                    return
                }
                discoveredTests.withLock { $0 += 1 }
            }
            let testCount = discoveredTests.withLock { $0 }
            restorePreviousApplication()
            if passed, testCount == 0 {
                exit(EX_UNAVAILABLE)
            }
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        } catch {
            FileHandle.standardError.write(Data("LittleSwitchUITestHost: \(error)\n".utf8))
            restorePreviousApplication()
            exit(2)
        }
    }

    private func activateApplication() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "LittleSwitch UI Tests"
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        hostWindow = window
        NSApp.activate()
    }

    private func restorePreviousApplication() {
        hostWindow?.close()
        hostWindow = nil
        guard NSApp.isActive, let previousApplication else { return }
        NSApp.yieldActivation(to: previousApplication)
        _ = previousApplication.activate(options: [])
    }
}

@main
private struct LittleSwitchUITestHost {
    @MainActor
    static func main() {
        if let status = TestHostLauncher.runFirstStageIfNecessary() {
            exit(status)
        }
        let testExecutable = ProcessInfo.processInfo.environment["LITTLESWITCH_SWIFT_TEST_EXECUTABLE"]
        let isUITestBundle =
            testExecutable?.hasSuffix("/LittleSwitchUITests.xctest/Contents/MacOS/LittleSwitchUITests")
            == true
        let application = NSApplication.shared
        application.setActivationPolicy(isUITestBundle ? .regular : .accessory)
        let delegate = TestHostDelegate(activatesApplication: isUITestBundle)
        application.delegate = delegate
        delegate.start()
        withExtendedLifetime(delegate) {
            application.run()
        }
        exit(2)
    }
}
