import Foundation
import LittleSwitchSearch
import LittleSwitchWire

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
    static func requireBridgeableCallers(for tool: [String: JSONValue]) throws {
        guard let rawCallers = tool[AnthropicSearchToolConfiguration.Key.allowedCallers.rawValue] else {
            return
        }
        guard let callers = rawCallers.array, callers.allSatisfy({ $0.string != nil }) else {
            throw Error.invalidMessage
        }
    }

    static func searchOptions(
        from tool: [String: JSONValue]
    ) throws -> WebSearchFilterOptions {
        let hasAllowedDomains = tool[AnthropicSearchToolConfiguration.Key.allowedDomains.rawValue] != nil
        let hasBlockedDomains = tool[AnthropicSearchToolConfiguration.Key.blockedDomains.rawValue] != nil
        guard !(hasAllowedDomains && hasBlockedDomains) else {
            throw Error.invalidMessage
        }

        let includeDomains = try domainList(tool[AnthropicSearchToolConfiguration.Key.allowedDomains.rawValue])
        let excludeDomains = try domainList(tool[AnthropicSearchToolConfiguration.Key.blockedDomains.rawValue])
        let location = try approximateLocation(tool[AnthropicSearchToolConfiguration.Key.userLocation.rawValue])
        return WebSearchFilterOptions(
            includeDomains: includeDomains,
            excludeDomains: excludeDomains,
            location: location.location,
            country: location.country
        )
    }

    private static func domainList(_ value: JSONValue?) throws -> [String]? {
        guard let value else {
            return nil
        }
        guard let values = value.array, values.allSatisfy({ $0.string != nil }) else {
            throw Error.invalidMessage
        }
        let domains = values.compactMap(\.string)
        return try domains.map { domain in
            let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw Error.invalidMessage
            }
            return normalized
        }
    }

    private static func approximateLocation(
        _ value: JSONValue?
    ) throws -> (location: String?, country: String?) {
        guard let value else {
            return (nil, nil)
        }
        guard let object = value.anthropicObject,
            object[AnthropicSearchUserLocation.Key.type.rawValue]?.string
                == AnthropicSearchLocationType.approximate.rawValue
        else {
            throw Error.invalidMessage
        }
        let city = try optionalNonemptyString(object[AnthropicSearchUserLocation.Key.city.rawValue])
        let region = try optionalNonemptyString(object[AnthropicSearchUserLocation.Key.region.rawValue])
        let country = try optionalNonemptyString(object[AnthropicSearchUserLocation.Key.country.rawValue])
        _ = try optionalNonemptyString(object[AnthropicSearchUserLocation.Key.timezone.rawValue])
        let joinedLocation = [city, region].compactMap(\.self).joined(separator: ", ")
        return (joinedLocation.isEmpty ? nil : joinedLocation, country)
    }

    private static func optionalNonemptyString(_ value: JSONValue?) throws -> String? {
        guard let value else {
            return nil
        }
        guard let string = value.string else {
            throw Error.invalidMessage
        }
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw Error.invalidMessage
        }
        return normalized
    }
}
