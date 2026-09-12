extension ProviderToolContract.Error: CustomStringConvertible {
    /// Error descriptions remain content-free. Tool identity is available only
    /// through the associated values for explicit, local diagnostic recording.
    package var description: String {
        switch self {
        case .invalidRequest: "invalidRequest"
        case .invalidResponse: "invalidResponse"
        case .undeclaredTool: "undeclaredTool"
        case .providerOwnedTool: "providerOwnedTool"
        }
    }
}
