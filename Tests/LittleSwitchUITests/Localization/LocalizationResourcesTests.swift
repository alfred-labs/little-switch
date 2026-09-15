import Foundation
import Testing

@testable import LittleSwitchUI

@Suite("UI localization resources")
struct LocalizationResourcesTests {
    @Test("The UI localization resources contain complete English and French values")
    func localizationResourcesContainEnglishAndFrench() throws {
        let resourceRoot = RepositorySources.root
            .appendingPathComponent("Sources/LittleSwitchUI/Resources")
        let englishURL =
            resourceRoot
            .appendingPathComponent("en.lproj/Localizable.strings")
        let frenchURL =
            resourceRoot
            .appendingPathComponent("fr.lproj/Localizable.strings")

        #expect(FileManager.default.fileExists(atPath: englishURL.path))
        #expect(FileManager.default.fileExists(atPath: frenchURL.path))

        let english = try dictionary(at: englishURL)
        let french = try dictionary(at: frenchURL)

        #expect(english["Apply changes"] == "Apply changes")
        #expect(french["Apply changes"] == "Appliquer les modifications")
    }

    @Test("Localized text resolves through the UI module bundle")
    func localizedTextResolvesThroughModuleBundle() {
        let english = L10n.resource("Apply changes", locale: Locale(identifier: "en"))
        let french = L10n.resource("Apply changes", locale: Locale(identifier: "fr"))
        let frenchModels = L10n.resource(
            "\(2) models",
            locale: Locale(identifier: "fr")
        )

        #expect(String(localized: english) == "Apply changes")
        #expect(String(localized: french) == "Appliquer les modifications")
        #expect(String(localized: frenchModels) == "2 modèles")
    }

    @Test("Every UI localization key has parallel nonempty values")
    func everyUILocalizationKeyHasParallelNonemptyValues() throws {
        let resourceRoot = RepositorySources.root
            .appendingPathComponent("Sources/LittleSwitchUI/Resources")
        let english = try dictionary(
            at: resourceRoot.appendingPathComponent("en.lproj/Localizable.strings")
        )
        let french = try dictionary(
            at: resourceRoot.appendingPathComponent("fr.lproj/Localizable.strings")
        )

        #expect(!english.isEmpty)
        #expect(Set(english.keys) == Set(french.keys))
        #expect(english.values.allSatisfy { !$0.isEmpty })
        #expect(french.values.allSatisfy { !$0.isEmpty })
        for (key, value) in english {
            let expected = placeholders(in: key)
            #expect(placeholders(in: value) == expected)
            #expect(placeholders(in: french[key] ?? "") == expected)
        }
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
}
