import Foundation
import HTTPTypes
import Testing

@testable import LittleSwitchCore

struct ChatGPTRequestBoundaryTests {
    @Test func keepsNativePathsAndQueryOnTheFixedOrigin() throws {
        #expect(
            try ChatGPTRequestBoundary.upstreamURL(path: "/backend-api/models?iim=false&include_icons=false")
                == "https://chatgpt.com/backend-api/models?iim=false&include_icons=false"
        )
        #expect(
            try ChatGPTRequestBoundary.upstreamURL(path: "/backend-api/conversation/a%20b")
                == "https://chatgpt.com/backend-api/conversation/a%20b"
        )
    }

    @Test(arguments: [
        "https://example.invalid/backend-api/models", "//example.invalid/backend-api/models",
        "/backend-api/../private", "/backend-api/%2e%2e/private", "/backend-api/%2fprivate",
        "/backend-api/%5cprivate", "/backend-api/./models", "/backend-api/models#fragment",
        "/backend-api/models\r\nx-test:value", "/backend-api/models%", "/models", "/backend-api//models",
    ])
    func rejectsAmbiguousOrNonBackendPaths(path: String) {
        #expect(throws: ChatGPTRequestBoundary.Error.invalidPath) {
            try ChatGPTRequestBoundary.upstreamURL(path: path)
        }
    }

    @Test func partitionsByUserAndAccountAcrossTokenRefresh() throws {
        let accountHeader = try #require(HTTPField.Name("chatgpt-account-id"))
        let first = try ChatGPTRequestBoundary.accountPartition(headers: [
            .authorization: token(subject: "user-one", expiry: 1), accountHeader: "workspace-one",
        ])
        let refreshed = try ChatGPTRequestBoundary.accountPartition(headers: [
            .authorization: token(subject: "user-one", expiry: 2), accountHeader: "workspace-one",
        ])
        let otherAccount = try ChatGPTRequestBoundary.accountPartition(headers: [
            .authorization: token(subject: "user-one", expiry: 1), accountHeader: "workspace-two",
        ])
        let otherUser = try ChatGPTRequestBoundary.accountPartition(headers: [
            .authorization: token(subject: "user-two", expiry: 1), accountHeader: "workspace-one",
        ])
        #expect(first == refreshed)
        #expect(first != otherAccount)
        #expect(first != otherUser)
        #expect(first.count == 64)
        #expect(first.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func opaqueSessionsStaySeparateAndAbsentSessionsFail() throws {
        let first = try ChatGPTRequestBoundary.accountPartition(headers: [.authorization: "Bearer synthetic-one"])
        #expect(first != "synthetic-one")
        #expect(
            try ChatGPTRequestBoundary.accountPartition(headers: [.authorization: "Bearer synthetic-two"]) != first
        )
        for headers: HTTPFields in [[:], [.authorization: "Bearer "], [.authorization: "Basic synthetic"]] {
            #expect(throws: ChatGPTRequestBoundary.Error.missingSession) {
                try ChatGPTRequestBoundary.accountPartition(headers: headers)
            }
        }
    }

    private func token(subject: String, expiry: Int) -> String {
        let payload = Data("{\"sub\":\"\(subject)\",\"exp\":\(expiry)}".utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        return "Bearer e30.\(payload).synthetic-signature"
    }
}
