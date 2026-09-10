import Foundation

/// The diagnostic retains number tokens and Unicode scalar identity rather than
/// bridging them through NSNumber or canonically equivalent Swift dictionary keys.
indirect enum DiagnosticJSON {
    case object([(String, DiagnosticJSON)])
    case array([DiagnosticJSON])
    case string(String)
    case scalar(String)

    subscript(key: String) -> DiagnosticJSON? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.last { $0.0.utf8.elementsEqual(key.utf8) }?.1
    }

    var elements: [DiagnosticJSON]? {
        guard case .array(let elements) = self else { return nil }
        return elements
    }

    var text: String? {
        guard case .string(let text) = self else { return nil }
        return text
    }
}
