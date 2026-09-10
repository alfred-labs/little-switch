import AppKit
import SwiftUI

// Native template of LobeHub Icons' MIT-licensed Exa mono mark.
// Catalog: https://lobehub.com/icons/exa
// Source: https://github.com/lobehub/lobe-icons/blob/
// 4aaf4ee1fb2678a7f989ea570f0f6ce14a9abf75/src/Exa/components/Mono.tsx
struct ExaIcon: View {
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
          <path fill="#000000" fill-rule="evenodd" clip-rule="evenodd" d="M3 0h19v1.791L13.892 12 22 22.209V24H3V0z
            m9.62 10.348l6.589-8.557H6.03l6.59 8.557zM5.138 3.935v7.17h5.52l-5.52-7.17z
            m5.52 8.96h-5.52v7.17l5.52-7.17zM6.03 22.21l6.59-8.557 6.589 8.557H6.03z"/>
        </svg>
        """
}
