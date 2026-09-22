import Foundation

enum ClaudeManagedPreferences {
    static func restrictsOrganization(value: Any?, isForced: Bool) -> Bool {
        guard isForced else { return false }
        let values: [String]
        if let value = value as? String {
            values = [value]
        } else if let value = value as? [String] {
            values = value
        } else {
            return false
        }
        return values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
