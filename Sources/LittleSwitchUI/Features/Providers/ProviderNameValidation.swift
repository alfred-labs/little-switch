import Foundation
import LittleSwitchCore

/// Shared by the draft and the coordinator so preflight and commit agree.
enum ProviderNameValidation {
    static func message(_ name: String, providers: [Provider], excluding providerID: UUID?) -> String? {
        let normalized = normalized(name)
        guard !normalized.isEmpty else {
            return "Enter a provider name."
        }
        return providers.contains {
            $0.id != providerID && self.normalized($0.name).caseInsensitiveCompare(normalized) == .orderedSame
        } ? "A provider with this name already exists." : nil
    }

    static func availableCopyName(of name: String, providers: [Provider]) -> String {
        let base = "\(normalized(name)) copy"
        var candidate = base
        var suffix = 2
        while message(candidate, providers: providers, excluding: nil) != nil {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
