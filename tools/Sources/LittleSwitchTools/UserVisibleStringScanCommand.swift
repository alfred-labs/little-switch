import ArgumentParser
import Foundation
import RepositoryTooling

struct UserVisibleStringScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ui-strings",
        abstract: "Scan for user-visible string literals that bypass localization entry points."
    )

    @OptionGroup var options: RepositoryOptions

    @Argument(help: "Directory to scan, relative to the repository root.")
    var directory: String = "Sources/LittleSwitchUI"

    func run() throws {
        let target = options.resolve(directory)
        let findings = try UserVisibleStringScanner.scan(directory: target)
        guard !findings.isEmpty else {
            print("No user-visible string findings in \(directory).")
            return
        }
        for finding in findings {
            // Interpolated literals localize through their static segments.
            let segments = finding.staticSegments.joined(separator: " ⟦…⟧ ")
            print(finding.description + (segments.isEmpty ? "" : " segments: \(segments)"))
        }
        print("\n\(findings.count) finding(s).")
    }
}
