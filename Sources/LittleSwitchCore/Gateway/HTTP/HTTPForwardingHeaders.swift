import Foundation
import HTTPTypes
import NIOHTTP1

package enum HTTPForwardingHeaders {
    package static func endToEnd(_ incoming: HTTPHeaders) -> HTTPHeaders {
        var forwarded = incoming
        let nominated = incoming[HTTPField.Name.connection.rawName].flatMap { value in
            value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        }
        for name in [
            HTTPField.Name.connection.rawName, HTTPField.Name.contentLength.rawName, "host",
            "keep-alive", HTTPField.Name.proxyAuthenticate.rawName,
            HTTPField.Name.proxyAuthorization.rawName,
            HTTPField.Name.te.rawName, HTTPField.Name.trailer.rawName, HTTPField.Name.transferEncoding.rawName,
            HTTPField.Name.upgrade.rawName,
        ] + nominated {
            forwarded.remove(name: name)
        }
        return forwarded
    }
}
