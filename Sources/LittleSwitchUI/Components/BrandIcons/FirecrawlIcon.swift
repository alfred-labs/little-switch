import AppKit
import SwiftUI

// Focused native asset sourced from LobeHub Icons' MIT-licensed Firecrawl mono
// icon, rendered as an AppKit template so the owning control supplies the
// semantic tint.
// Catalog: https://lobehub.com/icons/firecrawl
// Source: https://github.com/lobehub/lobe-icons/blob/
// 4aaf4ee1fb2678a7f989ea570f0f6ce14a9abf75/src/Firecrawl/components/Mono.tsx
struct FirecrawlIcon: View {
    var body: some View {
        Group {
            if let image = Self.templateImage() {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
        .accessibilityHidden(true)
    }

    static func templateImage() -> NSImage? {
        guard let image = NSImage(data: Data(svg.utf8)) else { return nil }
        image.isTemplate = true
        return image
    }

    private static let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
          <path fill="#000000" fill-rule="evenodd" d="M18.183 7.67c-.939.278-1.647.905-2.166 1.586-.11.146-.343.036-.299-.143.993-4.058-.318-7.432-4.407-9.092
            a.272.272 0 00-.368.317C12.803 7.76 4.98 7.135 5.969 15.55a.17.17 0 01-.266.159c-.37-.265-.784-.817-1.068-1.205a.17.17 0 00-.302.054
            A8.631 8.631 0 004 16.9a8.43 8.43 0 003.843 7.07c.133.086.303-.038.258-.189a4.533 4.533 0 01-.133-2.041c.097-.637.32-1.244.694-1.797
            1.283-1.914 3.854-3.763 3.443-6.273-.026-.16.162-.264.281-.155 1.812 1.645 2.17 3.858 1.873 5.844-.026.172.192.264.302.129.277-.345
            .615-.647.983-.875a.17.17 0 01.25.088c.204.592.508 1.148.796 1.704a4.528 4.528 0 01.307 3.375.17.17 0 00.257.192A8.43 8.43 0 0021 16.9
            a8.746 8.746 0 00-.524-2.98c-.718-1.982-2.54-3.47-2.08-6.053a.17.17 0 00-.213-.195z"/>
        </svg>
        """
}
