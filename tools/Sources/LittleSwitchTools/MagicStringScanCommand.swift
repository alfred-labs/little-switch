import ArgumentParser
import Foundation
import RepositoryTooling

struct MagicStringScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "magic-strings",
        abstract: "Scan raw protocol dictionary keys and contextual discriminants."
    )

    @OptionGroup var options: RepositoryOptions

    @Argument(help: "Directory to scan, relative to the repository root.")
    var directory: String?

    @Flag(help: "Create the initial occurrence baseline for protocol, tool, and gateway adapters.")
    var initializeBaseline = false

    @Flag(help: "Prune resolved occurrences from the baseline; reject new occurrences.")
    var updateBaseline = false

    mutating func validate() throws {
        guard !(initializeBaseline && updateBaseline) else {
            throw ValidationError("Choose only one baseline action.")
        }
        guard directory == nil || !(initializeBaseline || updateBaseline) else {
            throw ValidationError("Baseline actions scan the full adapter scope and do not accept a directory.")
        }
    }

    func run() throws {
        if initializeBaseline || updateBaseline {
            let count = try MagicStringPolicy.updateBaseline(
                root: options.resolve("."), action: initializeBaseline ? .initialize : .prune
            )
            if initializeBaseline {
                print("Created magic string baseline with \(count) occurrence(s).")
            } else {
                print("Updated magic string baseline to \(count) occurrence(s).")
            }
            return
        }
        let directory = directory ?? "Sources/LittleSwitchCore/Protocols"
        let target = options.resolve(directory)
        let catalogueURL = options.resolve(MagicStringPolicy.cataloguePath)
        let catalogue =
            FileManager.default.fileExists(atPath: catalogueURL.path)
            ? try MagicStringCatalogue(data: Data(contentsOf: catalogueURL)) : .empty
        let violations = try MagicKeyScanner.scan(directory: target, catalogue: catalogue)
        guard !violations.isEmpty else {
            print("No magic string violations found in \(directory).")
            return
        }
        for violation in violations {
            print(violation.description)
        }
        print("\n\(violations.count) violation(s) found.")
    }
}
