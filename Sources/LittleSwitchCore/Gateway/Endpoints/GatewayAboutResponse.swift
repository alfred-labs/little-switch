import HTTPTypes
import Hummingbird
import NIOCore

extension GatewayResponder {
    package func aboutResponse() -> Response {
        let object: [String: Any] = [
            "name": ProductIdentity.displayName,
            "version": ApplicationBuild.currentTag,
        ]
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: safeGatewayJSONData(object)))
        )
    }
}
