import Foundation
import LittleSwitchSearch

extension AnthropicWebSearch {
    /// Validates the caller policy the client declared on its built-in tool.
    ///
    /// `web_search_20260209` and later default `allowed_callers` to
    /// `["code_execution_20260120"]`: Anthropic runs those searches from
    /// inside server-side code execution — dynamic filtering — rather than
    /// calling the tool directly. This bridge owns no code-execution tool to
    /// host that loop, so a bridged search is always a direct call, and the
    /// projection labels every block `"caller": {"type": "direct"}`, the same
    /// shape the first-party API returns when dynamic filtering does not run.
    ///
    /// Serving the direct call costs the client only that filtering step.
    /// Refusing the tool version cost it the whole conversation: a client
    /// that upgraded answered HTTP 400 on every turn that declared the newer
    /// tool, search or no search. Only a malformed list is still rejected.
    static func requireBridgeableCallers(for tool: [String: Any]) throws {
        guard let rawCallers = tool["allowed_callers"] else {
            return
        }
        guard rawCallers is [String] else {
            throw Error.invalidMessage
        }
    }

    static func searchOptions(
        from tool: [String: Any]
    ) throws -> WebSearchFilterOptions {
        let hasAllowedDomains = tool["allowed_domains"] != nil
        let hasBlockedDomains = tool["blocked_domains"] != nil
        guard !(hasAllowedDomains && hasBlockedDomains) else {
            throw Error.invalidMessage
        }

        let includeDomains = try domainList(tool["allowed_domains"])
        let excludeDomains = try domainList(tool["blocked_domains"])
        let location = try approximateLocation(tool["user_location"])
        return WebSearchFilterOptions(
            includeDomains: includeDomains,
            excludeDomains: excludeDomains,
            location: location.location,
            country: location.country
        )
    }

    private static func domainList(_ value: Any?) throws -> [String]? {
        guard let value else {
            return nil
        }
        guard let domains = value as? [String] else {
            throw Error.invalidMessage
        }
        return try domains.map { domain in
            let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw Error.invalidMessage
            }
            return normalized
        }
    }

    private static func approximateLocation(
        _ value: Any?
    ) throws -> (location: String?, country: String?) {
        guard let value else {
            return (nil, nil)
        }
        guard let object = value as? [String: Any], object["type"] as? String == "approximate"
        else {
            throw Error.invalidMessage
        }
        let city = try optionalNonemptyString(object["city"])
        let region = try optionalNonemptyString(object["region"])
        let country = try optionalNonemptyString(object["country"])
        _ = try optionalNonemptyString(object["timezone"])
        let joinedLocation = [city, region].compactMap(\.self).joined(separator: ", ")
        return (joinedLocation.isEmpty ? nil : joinedLocation, country)
    }

    private static func optionalNonemptyString(_ value: Any?) throws -> String? {
        guard let value else {
            return nil
        }
        guard let string = value as? String else {
            throw Error.invalidMessage
        }
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw Error.invalidMessage
        }
        return normalized
    }
}
