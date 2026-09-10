import AsyncHTTPClient
import Foundation
import LittleSwitchTransport

public struct ProviderClient: Sendable {
    public enum Error: Swift.Error, Equatable {
        case httpStatus(Int)
    }

    private let transport: any UpstreamTransport
    private let maximumCatalogBytes: Int

    public init(
        transport: any UpstreamTransport,
        maximumCatalogBytes: Int = 8 * 1_024 * 1_024
    ) {
        self.transport = transport
        self.maximumCatalogBytes = maximumCatalogBytes
    }

    public func discover(provider: Provider, secret: String?) async throws -> [DiscoveredModel] {
        let request = try ProviderRequestBuilder.discovery(provider: provider, secret: secret)
        let data = try await requiredData(for: request)
        let models = try ProviderCatalog.parse(data)
        guard models.contains(where: { $0.detectedContextWindow == nil }) else {
            return models
        }
        return try await enrichOllamaContexts(
            models,
            provider: provider,
            secret: secret
        )
    }

    private func requiredData(for request: HTTPClientRequest) async throws -> Data {
        let response = try await transport.execute(request)
        guard (200..<300).contains(response.status.code) else {
            throw Error.httpStatus(Int(response.status.code))
        }
        return try await collect(response)
    }

    private func optionalData(for request: HTTPClientRequest) async throws -> Data? {
        let response: HTTPClientResponse
        do {
            response = try await transport.execute(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
        guard (200..<300).contains(response.status.code) else {
            return nil
        }
        do {
            return try await collect(response)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private func collect(_ response: HTTPClientResponse) async throws -> Data {
        let buffer = try await response.body.collect(upTo: maximumCatalogBytes)
        return Data(buffer.readableBytesView)
    }

    private func enrichOllamaContexts(
        _ models: [DiscoveredModel],
        provider: Provider,
        secret: String?
    ) async throws -> [DiscoveredModel] {
        guard
            let versionRequest = try? ProviderRequestBuilder.ollamaVersion(
                provider: provider,
                secret: secret
            ),
            let versionData = try await optionalData(for: versionRequest),
            ProviderCatalog.isOllamaVersion(versionData)
        else {
            return models
        }

        var enriched = models
        for index in enriched.indices where enriched[index].detectedContextWindow == nil {
            guard
                let showRequest = try? ProviderRequestBuilder.ollamaShow(
                    provider: provider,
                    secret: secret,
                    modelID: enriched[index].id
                ),
                let showData = try await optionalData(for: showRequest),
                let contextWindow = ProviderCatalog.parseOllamaContextWindow(showData)
            else {
                continue
            }
            enriched[index].detectedContextWindow = contextWindow
        }
        return enriched
    }
}
