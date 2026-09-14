/// Which header carries the provider credential, when one is saved.
///
/// A mode says where the key goes, never whether it is mandatory: an empty
/// credential simply sends no header, so a local server that accepts anonymous
/// requests and one that requires a key share the same setting. Where the
/// credential value comes from is `CredentialSource`, not this type.
public enum AuthMode: String, Codable, CaseIterable, Sendable {
    case none
    case bearer
    case xAPIKey = "x-api-key"

    /// Configurations written before the required and optional bearer modes
    /// merged still name the old value; both meant "Authorization: Bearer".
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "optional-bearer" {
            self = .bearer
            return
        }
        guard let mode = AuthMode(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unknown authentication mode \(raw)"
            )
        }
        self = mode
    }
}
