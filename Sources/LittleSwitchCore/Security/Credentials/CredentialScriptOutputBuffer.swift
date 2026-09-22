import Foundation

/// Limits retention as each chunk arrives, independently of when the pipe closes.
struct CredentialScriptOutputBuffer: Sendable {
    enum Retention: Sendable {
        case prefix(Int)
        case suffix(Int)
    }

    let retention: Retention
    private(set) var data = Data()
    private(set) var exceededLimit = false

    /// Returns true only for the first chunk that exceeds the retention limit.
    mutating func append(_ chunk: Data) -> Bool {
        let limit: Int
        switch retention {
        case .prefix(let count), .suffix(let count):
            limit = max(0, count)
        }
        let remaining = limit - data.count
        let firstExcess = !exceededLimit && chunk.count > remaining
        exceededLimit = exceededLimit || chunk.count > remaining
        switch retention {
        case .prefix:
            chunk.withUnsafeBytes { bytes in
                data.append(contentsOf: bytes.prefix(remaining))
            }
        case .suffix:
            if chunk.count >= limit {
                // Copy from bytes: a Data slice can otherwise keep the entire
                // oversized chunk's backing allocation alive.
                data = chunk.suffix(limit).withUnsafeBytes { Data($0) }
            } else {
                data = data.suffix(limit - chunk.count).withUnsafeBytes { Data($0) }
                data.append(chunk)
            }
        }
        return firstExcess
    }
}
