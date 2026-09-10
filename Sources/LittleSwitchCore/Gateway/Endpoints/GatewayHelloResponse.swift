import HTTPTypes
import Hummingbird
import NIOCore

extension GatewayResponder {
    /// `/api/hello` — the preconnect probe Claude Code fires at its
    /// configured base URL before gateway mode is ever established. The
    /// upstream API answers `200 {"message":"hello"}` and the client
    /// reads anything else as a failed probe, so the gateway mirrors that
    /// byte shape rather than a bare 204.
    package func helloResponse() -> Response {
        let object: [String: Any] = ["message": "hello"]
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(
                byteBuffer: ByteBuffer(bytes: safeGatewayJSONData(object))
            )
        )
    }
}
