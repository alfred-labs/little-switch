import Foundation

private enum LauncherError: Error {
    case missingTestExecutable
    case missingOptionValue(String)
}

enum TestHostLauncher {
    /// SwiftPM launches a toolset runner directly, before a shell can strip
    /// DYLD_* variables. Re-exec this same host with only Swift Testing args.
    static func runFirstStageIfNecessary() -> Int32? {
        var environment = ProcessInfo.processInfo.environment
        guard environment["LITTLESWITCH_SWIFT_TEST_EXECUTABLE"] == nil else { return nil }

        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let testExecutable = arguments.first else { throw LauncherError.missingTestExecutable }
            let forwarded = try testingArguments(afterTestExecutable: arguments.dropFirst())
            let canonicalExecutable = URL(fileURLWithPath: testExecutable).standardizedFileURL.path
            environment["LITTLESWITCH_SWIFT_TEST_EXECUTABLE"] = canonicalExecutable

            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = forwarded
            child.environment = environment
            try child.run()
            child.waitUntilExit()
            if child.terminationReason == .uncaughtSignal {
                return 128 + child.terminationStatus
            }
            return child.terminationStatus
        } catch {
            FileHandle.standardError.write(Data("LittleSwitchUITestHost launcher: \(error)\n".utf8))
            return 2
        }
    }

    private static func testingArguments(afterTestExecutable arguments: ArraySlice<String>) throws -> [String] {
        var forwarded: [String] = []
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--toolset", "--scratch-path", "--cache-path", "--config-path", "--security-path", "--sanitize",
                "-Xswiftc":
                guard iterator.next() != nil else { throw LauncherError.missingOptionValue(argument) }
            case "--disable-sandbox", "--disable-xctest", "--enable-code-coverage":
                break
            default:
                forwarded.append(argument)
            }
        }
        return forwarded
    }
}
