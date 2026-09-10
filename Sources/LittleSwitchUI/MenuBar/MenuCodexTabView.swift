import AppKit
import LittleSwitchCore
import SwiftUI

/// The menu's Codex tab: token consumption above the default and review model
/// settings, with the existing Apply action for pending changes.
/// Fixed composition, so the hosting height never moves.
struct MenuCodexTabView: View {
    @Bindable private var model: AppModel
    private let onDefault: @MainActor (ModelMapping?) async -> Void
    private let onAutoReview: @MainActor (ModelMapping?) async -> Void
    private let onApplyCodex: @MainActor () async -> Void

    init(
        model: AppModel,
        onDefault: @escaping @MainActor (ModelMapping?) async -> Void,
        onAutoReview: @escaping @MainActor (ModelMapping?) async -> Void,
        onApplyCodex: @escaping @MainActor () async -> Void
    ) {
        self.model = model
        self.onDefault = onDefault
        self.onAutoReview = onAutoReview
        self.onApplyCodex = onApplyCodex
    }

    /// Mirrors the body below block for block; the hosting view's frame
    /// sizes the item, and the height test measures the unframed body
    /// against this constant, so anything added to the body has to be added
    /// here too.
    static let height: CGFloat =
        MenuTabContentLayout.verticalPadding * 2
        + MenuUsageStatsBlock.fixedHeight
        + MenuSettingsSectionHeader.height
        + MenuTabContentLayout.rowHeight * 2
        + MenuTabContentLayout.rowSpacing
        + MenuTabContentLayout.actionRowHeight

    var body: some View {
        VStack(spacing: 0) {
            consumptionBlock
            MenuSettingsSectionHeader()
            Grid(horizontalSpacing: 0, verticalSpacing: MenuTabContentLayout.rowSpacing) {
                defaultModelRow
                MenuCodexReviewModelRow(model: model, onSelect: onAutoReview)
            }
            .padding(.horizontal, MenuStatsBlockLayout.horizontalPadding)
            .disabled(model.isBusy)
            actionRow
        }
        .padding(.vertical, MenuTabContentLayout.verticalPadding)
        .frame(width: StatusMenuLayout.width)
        .accessibilityElement(children: .contain)
    }

    private var consumption: GatewayUsageStatsPresentation {
        GatewayUsageStatsPresentation(
            summary: model.gatewayClientUsage[.codex]
                ?? GatewayUsageSummary(
                    history: GatewayUsageHistory(),
                    client: .codex,
                    now: Date()
                )
        )
    }

    private var consumptionBlock: some View {
        MenuUsageStatsBlock(stats: consumption)
            .padding(.horizontal, MenuStatsBlockLayout.horizontalPadding)
    }

    private var defaultModelRow: some View {
        GridRow {
            Text("Default model")
                .font(.system(size: 12, weight: .medium))
                .fixedSize()
                .frame(height: MenuTabContentLayout.rowHeight)
                .gridColumnAlignment(.leading)
            MenuMappingArrow()
            if model.codexExposedModelOptions.isEmpty {
                MenuModelLoadingPlaceholder()
            } else {
                MenuModelStepper(
                    name: "Default model",
                    options: codexOptions,
                    selection: Binding<MenuModelOption?>(
                        get: {
                            codexOptions.first { $0.id == model.codexDefaultOptionID }
                        },
                        set: { option in
                            Task { await onDefault(option?.mapping) }
                        }
                    ),
                    width: MenuTabContentLayout.mappingPickerWidth
                )
            }
        }
    }

    private var codexOptions: [MenuModelOption] {
        model.codexExposedModelOptions.map { option in
            MenuModelOption(id: option.id, label: option.label, mapping: option.mapping)
        }
    }

    private var actionRow: some View {
        HStack {
            if model.hasUnavailableCodexAutoReviewModel {
                Text("Review model unavailable")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            } else if model.hasPendingCodexChanges {
                Text("Changes pending")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            MenuApplyButton(action: .codex(model: model, onApply: onApplyCodex))
        }
        .padding(.horizontal, MenuStatsBlockLayout.horizontalPadding)
        .frame(width: StatusMenuLayout.width, height: MenuTabContentLayout.actionRowHeight)
    }
}
