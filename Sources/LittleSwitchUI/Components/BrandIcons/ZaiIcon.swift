import AppKit
import SwiftUI

// LobeHub Icons (MIT), ZAI monochrome mark.
// Catalog: https://lobehub.com/icons/zai
// Source: https://github.com/lobehub/lobe-icons/blob/
// 4aaf4ee1fb2678a7f989ea570f0f6ce14a9abf75/src/ZAI/components/Mono.tsx
struct ZaiIcon: View {
    var body: some View {
        if let image = Self.templateImage() {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        }
    }

    static func templateImage() -> NSImage? {
        guard let image = NSImage(data: Data(svg.utf8)) else { return nil }
        image.isTemplate = true
        return image
    }

    private static let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000" fill-rule="evenodd">
          <path d="M 12.105 2 L 9.927 4.953 H .653 L 2.83 2 h 9.276 z M 23.254 19.048 L 21.078 22 h -9.242 l 2.174 -2.952 h 9.244 z M 24 2 L 9.264 22 H 0 L 14.736 2 H 24 z"/>
        </svg>
        """
}
