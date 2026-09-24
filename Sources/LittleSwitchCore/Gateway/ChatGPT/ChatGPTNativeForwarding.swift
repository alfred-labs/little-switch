import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import NIOHTTP1

extension ChatGPTGatewayResponder {
    func nativeRequest(_ request: Request, url: String, body: Data) -> HTTPClientRequest {
        var forwarded = HTTPClientRequest(url: url)
        forwarded.method = HTTPMethod(rawValue: request.method.rawValue)
        forwarded.headers = HTTPForwardingHeaders.endToEnd(
            HTTPHeaders(request.headers.map { ($0.name.rawName, $0.value) })
        )
        // Catalogs change with the local configuration independently of the
        // native ETag. Request identity encoding for deterministic transforms.
        if isCatalog(request) {
            forwarded.headers.remove(name: "if-none-match")
            forwarded.headers.remove(name: "if-modified-since")
        }
        forwarded.headers.replaceOrAdd(name: "accept-encoding", value: "identity")
        if !body.isEmpty { forwarded.body = .bytes(body) }
        return forwarded
    }

    func nativeResponse(_ upstream: HTTPClientResponse) -> Response {
        Response(
            status: HTTPResponse.Status(code: Int(upstream.status.code)),
            headers: nativeResponseHeaders(upstream.headers),
            body: ResponseBody { writer in
                for try await buffer in upstream.body {
                    try Task.checkCancellation()
                    try await writer.write(buffer)
                }
                try await writer.finish(nil)
            }
        )
    }

    func nativeResponseHeaders(_ incoming: HTTPHeaders) -> HTTPFields {
        var fields = HTTPFields()
        for header in HTTPForwardingHeaders.endToEnd(incoming) {
            guard let name = HTTPField.Name(header.name) else { continue }
            let value = name == .setCookie ? ChatGPTNativeCookie.localHeader(header.value) : header.value
            if let value { fields.append(HTTPField(name: name, value: value)) }
        }
        return fields
    }

    func nativeJSONResponse(_ data: Data, headers incoming: HTTPHeaders) -> Response {
        var headers = nativeResponseHeaders(incoming)
        headers[.eTag] = nil
        headers[.lastModified] = nil
        headers[.contentEncoding] = nil
        headers[.contentType] = "application/json"
        headers[.cacheControl] = "no-store"
        return Response(status: .ok, headers: headers, body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
    }

    func isCatalog(_ request: Request) -> Bool {
        request.method == .get && request.uri.path == "/backend-api/models"
    }

    func errorResponse(_ status: HTTPResponse.Status, _ message: String) throws -> Response {
        // Messages are fixed by the adapter, never derived from request/auth
        // values or remote error bodies.
        let data = try JSONEncoder().encode([ChatGPTNativeContract.EventField.detail.rawValue: message])
        return Response(
            status: status,
            headers: [.contentType: "application/json", .cacheControl: "no-store"],
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: data))
        )
    }
}
