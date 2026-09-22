/// A readable, injective encoding of the two managed-model name components.
/// Model IDs are case-sensitive even when a client compares catalog slugs
/// case-insensitively. Escapes use lowercase ASCII and also escape literal `%`.
/// No encoded identifier contains `/`, keeping it disjoint from legacy aliases.
public enum ManagedModelIdentifier {
    public static func make(providerName: String, modelID: String) -> String {
        encode(providerName.lowercased()) + ":" + encode(modelID)
    }

    /// The one raw separator is reserved even if a component has malformed
    /// escapes or is empty. An unavailable or damaged managed identifier must
    /// not become a native upstream request. Multi-colon native IDs stay outside
    /// this namespace; encoded components never contain a raw colon themselves.
    public static func usesCanonicalNamespace(_ identifier: String) -> Bool {
        var foundSeparator = false
        for byte in identifier.utf8 where byte == UInt8(ascii: ":") {
            if foundSeparator { return false }
            foundSeparator = true
        }
        return foundSeparator
    }

    private static func encode(_ value: String) -> String {
        let encodedBytes = value.utf8.map { byte in
            switch byte {
            case 97...122, 48...57, 45, 46, 95, 64, 43, 126:
                return String(UnicodeScalar(byte))
            default:
                return "%" + (byte < 16 ? "0" : "") + String(byte, radix: 16)
            }
        }
        return encodedBytes.joined()
    }
}
