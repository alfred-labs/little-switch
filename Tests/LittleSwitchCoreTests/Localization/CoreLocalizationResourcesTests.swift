import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Core localization resources")
struct CoreLocalizationResourcesTests {
    @Test("Core user-facing errors localize through the module bundle")
    func coreUserFacingErrorsLocalizeThroughModuleBundle() throws {
        let resourceRoot = packageRoot().appendingPathComponent("Sources/LittleSwitchCore/Resources")
        let englishURL =
            resourceRoot
            .appendingPathComponent("en.lproj/Localizable.strings")
        let frenchURL =
            resourceRoot
            .appendingPathComponent("fr.lproj/Localizable.strings")

        #expect(FileManager.default.fileExists(atPath: englishURL.path))
        #expect(FileManager.default.fileExists(atPath: frenchURL.path))
        let english = try dictionary(at: englishURL)
        let frenchValues = try dictionary(at: frenchURL)

        #expect(!english.isEmpty)
        #expect(Set(english.keys) == Set(frenchValues.keys))
        #expect(english.values.allSatisfy { !$0.isEmpty })
        #expect(frenchValues.values.allSatisfy { !$0.isEmpty })
        for (key, value) in english {
            let expected = placeholders(in: key)
            #expect(placeholders(in: value) == expected)
            #expect(placeholders(in: frenchValues[key] ?? "") == expected)
        }

        let key = "The credential script printed no token."
        #expect(english[key] == key)
        #expect(frenchValues[key] == "Le script d’identifiants n’a affiché aucun jeton.")

        let french = CoreL10n.string(
            "The credential script printed no token.",
            locale: Locale(identifier: "fr")
        )
        let exitStatus: Int32 = 7
        let localizedExitStatus = CoreL10n.string(
            "The credential script exited with status \(exitStatus).",
            locale: Locale(identifier: "fr")
        )
        #expect(french == "Le script d’identifiants n’a affiché aucun jeton.")
        #expect(localizedExitStatus == "Le script d’identifiants s’est terminé avec le code 7.")
    }

    private func dictionary(at url: URL) throws -> [String: String] {
        let source = try String(contentsOf: url, encoding: .utf8)
        return try PropertyListSerialization.propertyList(
            from: Data(source.utf8),
            format: nil
        ) as? [String: String] ?? [:]
    }

    private func placeholders(in value: String) -> [String] {
        let pattern = /%(\d+\$)?(lld|llu|d|@)/
        var matches: [(position: Int, type: String)] = []
        var implicitPosition = 0
        for match in value.matches(of: pattern) {
            implicitPosition += 1
            let position = match.1.flatMap { Int(String($0.dropLast())) } ?? implicitPosition
            matches.append((position, String(match.2)))
        }
        return matches.sorted { $0.position < $1.position }.map(\.type)
    }

    private func packageRoot() -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        preconditionFailure("Cannot locate the application package from its test sources")
    }
}
