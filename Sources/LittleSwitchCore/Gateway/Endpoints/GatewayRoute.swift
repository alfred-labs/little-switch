import Hummingbird

/// The request paths the gateway answers. The gateway's own routes come
/// from `ProductIdentity` so routing and usage accounting cannot drift,
/// and `/v1/` holds Anthropic and OpenAI contract routes only. The
/// `/_little_switch/*` names keep answering for clients that still hold a
/// pre-rename URL — one release, then the aliases retire together with
/// `ProductIdentity.legacyGatewayInternalPathPrefix`.
package enum GatewayRoute: Equatable, Sendable {
    case health
    case about
    case hello
    case managedWebSearch
    case webSearchMCP
    case models
    case countTokens
    case messages
    case responses
    case imageGenerations
    case imageEdits
    case metrics
    case logs

    package static func resolve(_ rawPath: String) -> GatewayRoute? {
        switch rawPath {
        case ProductIdentity.gatewayHealthPath:
            .health
        case ProductIdentity.gatewayMetricsPath:
            .metrics
        case ProductIdentity.gatewayLogsPath:
            .logs
        case ProductIdentity.gatewayAPIPathPrefix + "about":
            .about
        case ProductIdentity.gatewayAPIPathPrefix + "hello":
            .hello
        case ProductIdentity.gatewayAPIPathPrefix + "web-search":
            .managedWebSearch
        case ProductIdentity.gatewayAPIPathPrefix + "mcp":
            .webSearchMCP
        case "/v1/models":
            .models
        case "/v1/messages/count_tokens":
            .countTokens
        case "/v1/messages":
            .messages
        case "/v1/responses":
            .responses
        case "/v1/images/generations":
            .imageGenerations
        case "/v1/images/edits":
            .imageEdits
        case ProductIdentity.legacyGatewayInternalPathPrefix + "health":
            .health
        case ProductIdentity.legacyGatewayInternalPathPrefix + "about":
            .about
        case ProductIdentity.legacyGatewayInternalPathPrefix + "web_search":
            .managedWebSearch
        default:
            nil
        }
    }

    /// The method each route answers; `hello` additionally accepts HEAD —
    /// it is the client's preconnect probe, which fires HEAD and moves on.
    package func accepts(method: HTTPRequest.Method) -> Bool {
        if self == .hello, method == .head {
            return true
        }
        return method == self.method
    }

    var method: HTTPRequest.Method {
        switch self {
        case .about, .health, .hello, .models, .metrics, .logs:
            .get
        case .countTokens, .managedWebSearch, .webSearchMCP, .messages, .responses, .imageGenerations, .imageEdits:
            .post
        }
    }
}
