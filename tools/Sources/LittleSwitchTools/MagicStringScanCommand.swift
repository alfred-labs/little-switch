import ArgumentParser
import Foundation
import RepositoryTooling

struct MagicStringScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "magic-strings",
        abstract: "Scan for raw string literals used as dictionary keys in protocol Swift files."
    )

    @OptionGroup var options: RepositoryOptions

    @Argument(help: "Directory to scan, relative to the repository root.")
    var directory: String = "Sources/LittleSwitchCore/Protocols"

    func run() throws {
        let target = options.resolve(directory)
        let violations = try MagicKeyScanner.scan(directory: target)
        guard !violations.isEmpty else {
            print("No magic key violations found in \(directory).")
            return
        }
        for violation in violations {
            print(violation.description)
        }
        print("\n\(violations.count) violation(s) found.")
    }
}
