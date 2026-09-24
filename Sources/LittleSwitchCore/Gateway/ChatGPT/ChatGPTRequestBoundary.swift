import Crypto
import Foundation
import HTTPTypes

package enum ChatGPTRequestBoundary {
    package enum Error: Swift.Error, Equatable {
        case invalidPath
        case missingSession
    }

    package static func upstreamURL(path: String) throws -> String {
        guard path.hasPrefix("/backend-api/"), !path.contains("#"),
            !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
            path.removingPercentEncoding != nil
        else { throw Error.invalidPath }
        let pathname = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let components = pathname.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        for (index, component) in components.enumerated() {
            guard let decoded = String(component).removingPercentEncoding,
                decoded != ".", decoded != "..", !decoded.contains("/"), !decoded.contains("\\"),
                !decoded.contains("%"), !decoded.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                !decoded.isEmpty || index == components.count - 1
            else { throw Error.invalidPath }
        }
        return "https://chatgpt.com" + path
    }

    package static func accountPartition(headers: HTTPFields) throws -> String {
        guard let authorization = headers[.authorization], authorization.utf8.count <= 32_768,
            authorization.lowercased().hasPrefix("bearer ")
        else { throw Error.missingSession }
        let token = String(authorization.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw Error.missingSession }
        let account = HTTPField.Name("chatgpt-account-id").flatMap { headers[$0] } ?? ""
        guard account.utf8.count <= 256 else { throw Error.missingSession }
        // This is a stable storage namespace, never an authentication verdict.
        // Session headers only travel to the official native backend.
        let user = subject(token) ?? token
        let identity = try JSONEncoder().encode(["chatgpt-history-v1", user, account])
        return SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
    }

    private static func subject(_ token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.utf8.count % 4) % 4)
        guard let bytes = Data(base64Encoded: payload),
            let claims = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
            let subject = claims[ChatGPTNativeContract.NamespaceClaim.sub.rawValue] as? String, !subject.isEmpty,
            subject.utf8.count <= 256
        else { return nil }
        return subject
    }
}
