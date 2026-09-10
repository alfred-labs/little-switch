import Foundation

struct CommitMessageReadError: LocalizedError {
    let path: String
    let reason: String

    var errorDescription: String? {
        "Cannot read commit message file at \(path): \(reason)"
    }
}
