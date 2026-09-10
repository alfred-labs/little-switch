import Foundation
import Testing

@testable import LittleSwitchCore

@Suite("Anthropic public sanitizer citation coverage")
struct AnthropicSanitizerCitationCoverageTests {
    @Test("Citation envelopes and web citation fields fail closed")
    func citationAndWebValidation() {
        let invalidEnvelopes: [Any] = [
            NSNull(),
            [String: Any](),
            ["type": 1],
        ]
        for citation in invalidEnvelopes {
            expectInvalidTextCitation(citation)
        }

        let validWeb: [String: Any] = [
            "type": "web_search_result_location",
            "url": "https://example.com/",
            "title": "Example",
            "cited_text": "Citation",
            "encrypted_index": "opaque",
        ]
        for key in ["url", "title", "cited_text", "encrypted_index"] {
            var citation = validWeb
            citation.removeValue(forKey: key)
            expectInvalidTextCitation(citation)
        }
    }

    @Test("Document citations validate identity, indices, and nullable strings")
    func documentCitationValidation() {
        let validChar: [String: Any] = [
            "type": "char_location",
            "cited_text": "Citation",
            "document_index": 0,
            "document_title": "Document",
            "file_id": NSNull(),
            "start_char_index": 0,
            "end_char_index": 1,
        ]
        var missingText = validChar
        missingText.removeValue(forKey: "cited_text")
        expectInvalidTextCitation(missingText)
        var missingDocumentIndex = validChar
        missingDocumentIndex.removeValue(forKey: "document_index")
        expectInvalidTextCitation(missingDocumentIndex)
        var negativeDocumentIndex = validChar
        negativeDocumentIndex["document_index"] = -1
        expectInvalidTextCitation(negativeDocumentIndex)
        var missingRange = validChar
        missingRange.removeValue(forKey: "start_char_index")
        expectInvalidTextCitation(missingRange)
        var negativeRange = validChar
        negativeRange["end_char_index"] = -1
        expectInvalidTextCitation(negativeRange)
        var invalidTitle = validChar
        invalidTitle["document_title"] = 1
        expectInvalidTextCitation(invalidTitle)
        var invalidFileID = validChar
        invalidFileID["file_id"] = 1
        expectInvalidTextCitation(invalidFileID)
    }

    @Test("Search-result citations validate every required field")
    func searchResultCitationValidation() {
        let valid: [String: Any] = [
            "type": "search_result_location",
            "cited_text": "Citation",
            "source": "source-id",
            "search_result_index": 0,
            "start_block_index": 0,
            "end_block_index": 1,
            "title": NSNull(),
        ]
        for key in [
            "cited_text",
            "source",
            "search_result_index",
            "start_block_index",
            "end_block_index",
        ] {
            var citation = valid
            citation.removeValue(forKey: key)
            expectInvalidTextCitation(citation)
        }
        for key in ["search_result_index", "start_block_index", "end_block_index"] {
            var citation = valid
            citation[key] = -1
            expectInvalidTextCitation(citation)
        }
        var invalidTitle = valid
        invalidTitle["title"] = 1
        expectInvalidTextCitation(invalidTitle)
    }
}

private func expectInvalidTextCitation(_ citation: Any) {
    #expect(throws: AnthropicWebSearch.Error.invalidMessage) {
        _ = try AnthropicPublicSanitizer.block([
            "type": "text",
            "text": "answer",
            "citations": [citation],
        ])
    }
}
