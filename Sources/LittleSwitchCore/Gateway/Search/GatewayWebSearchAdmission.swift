import Hummingbird
import LittleSwitchCommon

package enum GatewayWebSearchPreflight {
    case ready(searchCredential: String?)
    case rejected(Response)
}

extension GatewayResponder {
    package func webSearchPreflight(
        context: GatewayWebSearchContext
    ) -> GatewayWebSearchPreflight {
        let searchCredential: String?
        if context.prepared.maximumUses == 0 {
            searchCredential = nil
        } else if let credential = context.searchCredential {
            searchCredential = credential
        } else {
            do {
                searchCredential = try webSearchCredential(for: context.configuration)
            } catch {
                return .rejected(
                    anthropicError(
                        status: .internalServerError,
                        message: "Could not read web search credential"
                    )
                )
            }
        }
        guard context.prepared.upstreamBody.count <= maximumRequestBytes else {
            return .rejected(
                anthropicError(status: .contentTooLarge, message: "Request body is too large")
            )
        }
        do {
            _ = try ProviderRequestBuilder.message(
                provider: context.target.provider,
                secret: context.providerCredential,
                headers: context.incomingHeaders,
                body: context.prepared.upstreamBody
            )
        } catch {
            return .rejected(
                anthropicError(status: .serviceUnavailable, message: "Provider is not ready")
            )
        }
        return .ready(searchCredential: searchCredential)
    }
}
