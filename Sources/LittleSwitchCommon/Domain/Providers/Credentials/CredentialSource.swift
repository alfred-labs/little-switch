/// Where a provider's credential value comes from: typed into the editor
/// or produced by running the user's chosen script. Script sources require
/// an authentication mode that sends a header.
public enum CredentialSource: String, Codable, Sendable {
    case manual
    case script
}
