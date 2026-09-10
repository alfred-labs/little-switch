import AsyncHTTPClient
import Foundation

/// Translates model-discovery failures into actionable copy. Raw Swift
/// errors bridge to opaque system strings — "(AsyncHTTPClient.HTTPClientError
/// error 1.)" for transports, "The data couldn't be read because it is
/// missing." for decoding — which name neither the endpoint nor the cause.
public enum ProviderConnectionFailure {
    public static func message(for error: any Swift.Error) -> String? {
        if let clientError = error as? HTTPClientError {
            return "The provider connection failed: \(clientError.shortDescription)."
        }
        if case .httpStatus(let code) = error as? ProviderClient.Error {
            return "The endpoint answered with HTTP \(code) instead of a model catalog. "
                + "Check the Base URL and the credential."
        }
        if error is DecodingError {
            return "The endpoint answered, but not with a model catalog. "
                + "Check the Base URL points at an OpenAI-compatible API root."
        }
        return nil
    }
}
