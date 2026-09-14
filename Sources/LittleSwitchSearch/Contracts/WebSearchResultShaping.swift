import Foundation
import LittleSwitchCommon

/// Result shaping shared by every search provider: uniform validation plus a
/// single aggregate content budget so no provider can flood the model context.
package enum WebSearchResultShaping {
    private static let maximumTitleBytes = 4 * 1_024
    private static let maximumURLBytes = 8 * 1_024
    private static let truncationMarker = " [truncated]"

    package static func validated(
        title: String?,
        url: String?,
        content: String
    ) -> WebSearchResult? {
        guard
            let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty,
            title.utf8.count <= maximumTitleBytes,
            let url = url?.trimmingCharacters(in: .whitespacesAndNewlines),
            url.utf8.count <= maximumURLBytes,
            isHTTPURL(url)
        else {
            return nil
        }
        return WebSearchResult(title: title, url: url, content: content)
    }

    static func bounded(
        _ results: [WebSearchResult],
        limit: Int,
        maximumContentBytes: Int
    ) -> [WebSearchResult] {
        var remainingContentBytes = max(0, maximumContentBytes)
        var bounded: [WebSearchResult] = []
        bounded.reserveCapacity(min(limit, results.count))

        for var result in results {
            guard bounded.count < limit else {
                break
            }

            let contentBytes = result.content.utf8.count
            if contentBytes <= remainingContentBytes {
                remainingContentBytes -= contentBytes
            } else {
                result.content = truncatedContent(
                    result.content,
                    maximumBytes: remainingContentBytes
                )
                remainingContentBytes = 0
            }
            bounded.append(result)
        }
        return bounded
    }

    private static func truncatedContent(_ content: String, maximumBytes: Int) -> String {
        let markerBytes = truncationMarker.utf8.count
        guard markerBytes <= maximumBytes else {
            return validUTF8Prefix(content, maximumBytes: maximumBytes)
        }
        return validUTF8Prefix(content, maximumBytes: maximumBytes - markerBytes)
            + truncationMarker
    }

    private static func validUTF8Prefix(_ value: String, maximumBytes: Int) -> String {
        guard maximumBytes > 0 else {
            return ""
        }
        let scalars = value.unicodeScalars
        var end = scalars.startIndex
        var remainingBytes = maximumBytes
        while end != scalars.endIndex {
            let scalarBytes = scalars[end].utf8.count
            guard scalarBytes <= remainingBytes else {
                break
            }
            remainingBytes -= scalarBytes
            end = scalars.index(after: end)
        }
        return String(scalars[..<end])
    }

    private static func isHTTPURL(_ value: String) -> Bool {
        guard value.removingPercentEncoding != nil,
            let components = URLComponents(string: value),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            components.host?.isEmpty == false,
            components.user == nil,
            components.password == nil
        else {
            return false
        }
        return true
    }
}

extension String {
    package var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
