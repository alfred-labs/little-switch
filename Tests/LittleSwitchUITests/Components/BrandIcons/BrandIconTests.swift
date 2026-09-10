import AppKit
import SwiftUI
import Testing

@testable import LittleSwitchUI

/// The bundled brand marks are in-memory SVG documents decoded through
/// NSImage. A malformed string silently renders an empty slot — the exact
/// missing-icon class of bug these marks exist to prevent — so decoding is
/// asserted here, not assumed from compilation.
@Suite("Bundled brand marks")
struct BrandIconTests {
    @Test("Provider marks decode as square native template images")
    @MainActor
    func providerMarksDecode() throws {
        for candidate in [OllamaIcon.templateImage(), ZaiIcon.templateImage()] {
            let image = try #require(candidate)
            #expect(image.isTemplate)
            #expect(image.size.width > 0)
            #expect(image.size.width == image.size.height)
        }
    }

    @Test("The Codex knot decodes to a square image")
    @MainActor
    func codexKnotDecodes() throws {
        let image = try #require(NSImage(data: Data(CodexBrandMark.svg.utf8)))
        #expect(image.size.width > 0)
        #expect(abs(image.size.width - image.size.height) < 1)
    }

    @Test("The Claude mark decodes to a square image")
    @MainActor
    func claudeMarkDecodes() throws {
        let image = try #require(NSImage(data: Data(ClaudeIcon.svg.utf8)))
        #expect(image.size.width > 0)
        #expect(abs(image.size.width - image.size.height) < 1)
    }

    @Test("Each mark's body resolves to the image branch, not the empty failure branch")
    @MainActor
    func bodiesResolve() {
        let bodies: [any View] = [
            CodexIcon().body,
            ClaudeIcon().body,
        ]
        for body in bodies {
            let description = String(reflecting: type(of: body))
            #expect(description.contains("Image"), "the parsed mark should back the body")
            #expect(!description.contains("EmptyView"), "a failed parse must not pass silently")
        }
    }
}
