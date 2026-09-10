import AsyncHTTPClient
import Foundation
import NIOHTTP1

package protocol GatewayRetryRequestBuilding: Sendable {
    func message(
        provider: Provider,
        secret: String?,
        headers: HTTPHeaders,
        body: Data
    ) throws -> HTTPClientRequest
}

package struct LiveGatewayRetryRequestBuilder: GatewayRetryRequestBuilding {
    package init() {}

    package func message(
        provider: Provider,
        secret: String?,
        headers: HTTPHeaders,
        body: Data
    ) throws -> HTTPClientRequest {
        try ProviderRequestBuilder.message(
            provider: provider,
            secret: secret,
            headers: headers,
            body: body
        )
    }
}
