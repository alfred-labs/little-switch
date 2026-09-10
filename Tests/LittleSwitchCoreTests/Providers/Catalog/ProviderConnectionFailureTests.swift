import AsyncHTTPClient
import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Provider connection failure copy")
struct ProviderConnectionFailureTests {
    @Test("Transport failures describe the connection problem")
    func transportFailuresDescribe() {
        #expect(
            ProviderConnectionFailure.message(for: HTTPClientError.remoteConnectionClosed)
                == "The provider connection failed: Remote connection closed."
        )
        #expect(
            ProviderConnectionFailure.message(for: HTTPClientError.readTimeout)
                == "The provider connection failed: Read timeout."
        )
    }

    @Test("HTTP statuses and undecodable catalogs name the endpoint problem")
    func responseFailuresDescribe() {
        #expect(
            ProviderConnectionFailure.message(for: ProviderClient.Error.httpStatus(401))
                == "The endpoint answered with HTTP 401 instead of a model catalog. "
                + "Check the Base URL and the credential."
        )
        let decodingError = DecodingError.typeMismatch(
            Int.self,
            .init(codingPath: [], debugDescription: "not a catalog")
        )
        #expect(
            ProviderConnectionFailure.message(for: decodingError)
                == "The endpoint answered, but not with a model catalog. "
                + "Check the Base URL points at an OpenAI-compatible API root."
        )
    }

    @Test("Other errors stay nil so their own descriptions keep rendering")
    func otherErrorsStayNil() {
        struct UnrelatedError: Error {}

        #expect(ProviderConnectionFailure.message(for: UnrelatedError()) == nil)
        #expect(
            ProviderConnectionFailure.message(for: ProviderEndpoint.Error.invalidURL) == nil
        )
    }
}
