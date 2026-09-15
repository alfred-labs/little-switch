import AppKit
import SwiftUI

struct SettingsSplitView<Sidebar: View, Detail: View>: View {
    @Binding private var isSidebarVisible: Bool
    private let sidebar: Sidebar
    private let detail: Detail

    init(
        isSidebarVisible: Binding<Bool>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        _isSidebarVisible = isSidebarVisible
        self.sidebar = sidebar()
        self.detail = detail()
    }

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sidebar
                    .frame(width: SettingsLayout.sidebarIdealWidth)
                    .frame(maxHeight: .infinity)
                    .background {
                        Color(nsColor: SettingsLayout.Palette.sidebarBackground)
                            .ignoresSafeArea(edges: .top)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))

            }

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .background {
            Color(nsColor: SettingsLayout.Palette.detailBackground)
                .ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                if isSidebarVisible {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(
                            width: 1,
                            height: geometry.size.height + SettingsLayout.titlebarHeight
                        )
                        .offset(
                            x: SettingsLayout.sidebarIdealWidth - 1,
                            y: -SettingsLayout.titlebarHeight
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        .toolbar {
            sidebarToggleToolbarContent
        }
    }

    @ToolbarContentBuilder
    private var sidebarToggleToolbarContent: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) {
                sidebarToggleButton
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) {
                sidebarToggleButton
            }
        }
    }

    private var sidebarToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isSidebarVisible.toggle()
            }
        } label: {
            Image(systemName: "sidebar.left")
                .font(SettingsLayout.Typography.sidebarToggleIcon)
                .frame(
                    width: SettingsLayout.sidebarToggleSize,
                    height: SettingsLayout.sidebarToggleSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.leading, SettingsLayout.sidebarToggleToolbarLeadingPadding)
        .foregroundStyle(.secondary)
        .help(
            isSidebarVisible
                ? L10n.resource("Hide sidebar")
                : L10n.resource("Show sidebar")
        )
        .accessibilityLabel(
            isSidebarVisible
                ? L10n.resource("Hide sidebar")
                : L10n.resource("Show sidebar")
        )
    }
}
