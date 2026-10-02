import Foundation

extension Provider {
    /// Configuration changes that can replace the model behind an image observation.
    /// Explicit secret changes also require an owner-managed generation; secrets never belong in this value.
    public func hasSameImageInputIdentity(as other: Provider) -> Bool {
        id == other.id && baseURL == other.baseURL && anthropicBaseURL == other.anthropicBaseURL
            && authMode == other.authMode && credentialSource == other.credentialSource
            && credentialScriptPath == other.credentialScriptPath
            && responsesWireOverride == other.responsesWireOverride
    }
}
