import Foundation

enum ChatGPTNativeCookie {
    /// The upstream origin is pinned to chatgpt.com. Its domain cookies must
    /// become host-only cookies on the local HTTPS relay, or Chromium rejects
    /// registration before it can fetch the model catalog. Keep cookie values
    /// and all other attributes opaque, including expiration and deletion.
    static func localHeader(_ upstream: String) -> String? {
        let segments = upstream.components(separatedBy: ";")
        let cookie = segments[0]
        var retained = [cookie]
        for attribute in segments.dropFirst() {
            let pair = attribute.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair[0].trimmingCharacters(in: whitespace).lowercased() == "domain" else {
                retained.append(attribute)
                continue
            }
            guard pair.count == 2 else { return nil }
            let domain = pair[1].trimmingCharacters(in: whitespace).lowercased()
            // Reject foreign or ambiguous scopes, including conflicting
            // duplicate Domain attributes; never grant them localhost access.
            guard domain == "chatgpt.com" || domain == ".chatgpt.com" else { return nil }
            let name = cookie.prefix { $0 != "=" }.trimmingCharacters(in: whitespace).lowercased()
            // A host-prefixed cookie with Domain was already invalid upstream.
            // Removing that attribute must not make it valid on the relay.
            guard !name.hasPrefix("__host-") else { return nil }
        }
        return retained.joined(separator: ";")
    }

    private static let whitespace = CharacterSet(charactersIn: " \t")
}
