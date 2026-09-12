import AppKit
import LittleSwitchCore
import SwiftUI

enum AboutLayout {
    static let windowWidth: CGFloat = 420
    static let windowHeight: CGFloat = 320
    static let iconEdge: CGFloat = 96
    static let glyphInset: CGFloat = 24
    static let nameFontSize: CGFloat = 15
    static let detailFontSize: CGFloat = 11
    static let verticalSpacing: CGFloat = 12
    static let contentPadding: CGFloat = 24
}

struct AboutWindowContent: View {
    static let copyrightLine = "Copyright © 2026 LittleSwitch contributors"

    let displayName: String
    let buildTag: String
    let icon: NSImage?

    @MainActor
    static func current() -> AboutWindowContent {
        AboutWindowContent(
            displayName: ProductIdentity.displayName,
            buildTag: ApplicationBuild.currentTag,
            icon: NSApplication.shared.applicationIconImage
        )
    }

    var body: some View {
        VStack(spacing: AboutLayout.verticalSpacing) {
            iconView
                .frame(width: AboutLayout.iconEdge, height: AboutLayout.iconEdge)
                .accessibilityHidden(true)
            Text(displayName)
                .font(.system(size: AboutLayout.nameFontSize, weight: .semibold))
            Text("Version \(buildTag)")
                .font(.system(size: AboutLayout.detailFontSize))
                .foregroundStyle(.secondary)
            Text(Self.copyrightLine)
                .font(.system(size: AboutLayout.detailFontSize))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(AboutLayout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(nsImage: StatusItemIcon.makeImage(for: .idle))
                .resizable()
                .scaledToFit()
                .padding(AboutLayout.glyphInset)
        }
    }
}

@MainActor
enum AboutWindowFactory {
    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: AboutLayout.windowWidth,
                height: AboutLayout.windowHeight
            ),
            styleMask: [
                .titled,
                .closable,
            ],
            backing: .buffered,
            defer: false
        )
        window.title = "About \(ProductIdentity.displayName)"
        window.contentViewController = NSHostingController(
            rootView: AboutWindowContent.current()
        )
        window.setContentSize(
            NSSize(width: AboutLayout.windowWidth, height: AboutLayout.windowHeight)
        )
        window.center()
        window.isReleasedWhenClosed = false
        return window
    }
}
