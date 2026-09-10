/// What a Test click produced for a provider draft. Script failures and
/// authentication failures are distinct stages the editor reports separately:
/// a script can print a token while the endpoint refuses it.
enum ProviderTestOutcome: Equatable, Sendable {
    case passed(scriptOutput: String?)
    case scriptFailed(String)
    case authenticationFailed(String)
}
