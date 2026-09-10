import Hummingbird

extension GatewayResponder {
    package func modelsResponse() async throws -> Response {
        try Task.checkCancellation()
        let capture = try await dependencies.snapshotCapturer.capture(state: state)
        try Task.checkCancellation()
        do {
            let data = try dependencies.serializer.encodeCatalog(
                ClaudeCatalog.make(from: capture.snapshot)
            )
            return jsonResponse(status: .ok, data: data)
        } catch {
            return anthropicError(status: .internalServerError, message: "Could not encode model catalog")
        }
    }
}
