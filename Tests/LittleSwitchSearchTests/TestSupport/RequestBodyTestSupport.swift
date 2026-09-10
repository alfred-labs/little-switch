import AsyncHTTPClient
import Foundation

func recordedBody(_ body: HTTPClientRequest.Body?) async throws -> Data {
    var data = Data()
    guard let body else {
        return data
    }
    for try await var buffer in body {
        if let bytes = buffer.readBytes(length: buffer.readableBytes) {
            data.append(contentsOf: bytes)
        }
    }
    return data
}
