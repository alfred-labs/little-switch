import Hummingbird

extension GatewayResponder {
    package func modelsResponse(_ request: Request) async throws -> Response {
        try Task.checkCancellation()
        let capture = try await dependencies.snapshotCapturer.capture(state: state)
        try Task.checkCancellation()
        // Desktop expands supports_1m itself; Code discovery discards it.
        // Match the CLI's product token, not generic Claude user agents.
        let product = request.headers[.userAgent]?.split(whereSeparator: \.isWhitespace).first
        let cliPrefix = "claude-code/"
        let contextPresentation: ClaudeCatalog.ContextPresentation
        if let product, product.lowercased().hasPrefix(cliPrefix), product.count > cliPrefix.count {
            contextPresentation = .canonicalFamilyChoices
        } else {
            contextPresentation = .capabilities
        }
        do {
            let data = try dependencies.serializer.encodeCatalog(
                ClaudeCatalog.make(from: capture.snapshot, contextPresentation: contextPresentation)
            )
            var response = jsonResponse(status: .ok, data: data)
            response.headers[.vary] = "User-Agent"
            return response
        } catch {
            return anthropicError(status: .internalServerError, message: "Could not encode model catalog")
        }
    }
}
