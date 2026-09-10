import AppKit
import LittleSwitchCore
import SwiftUI

/// The menu's Claude tab: per-route model mappings with the same draft and
/// apply semantics as the settings pane, plus the Claude client's token
/// consumption. Fixed composition, so the hosting height never moves.
struct MenuClaudeTabView: View {
    @Bindable private var model: AppModel
    private let onMapping: @MainActor (String, ModelMapping?) async -> Void
    private let onApplyClaude:
        @MainActor (AppModel.ClaudePrimaryAction?, AppModel.ClaudeCodePrimaryAction?) async -> Void
    /// Cancels the open menu's tracking loop; the apply path confirms in a
    /// modal alert, which must not run under menu tracking.
    private let cancelTracking: @MainActor () -> Void

    init(
        model: AppModel,
        onMapping: @escaping @MainActor (String, ModelMapping?) async -> Void,
        onApplyClaude:
            @escaping @MainActor (
                AppModel.ClaudePrimaryAction?,
                AppModel.ClaudeCodePrimaryAction?
            ) async -> Void,
        cancelTracking: @escaping @MainActor () -> Void
    ) {
        self.model = model
        self.onMapping = onMapping
        self.onApplyClaude = onApplyClaude
        self.cancelTracking = cancelTracking
    }

    /// Mirrors the body below block for block; the hosting view's frame
    /// sizes the item, and the height test measures the unframed body
    /// against this constant, so anything added to the body has to be added
    /// here too.
    static let height: CGFloat =
        MenuTabContentLayout.verticalPadding * 2
        + MenuUsageStatsBlock.fixedHeight
        + MenuSettingsSectionHeader.height
        + MenuTabContentLayout.rowHeight * CGFloat(ClaudeRoute.all.count)
        + MenuTabContentLayout.rowSpacing * CGFloat(ClaudeRoute.all.count - 1)
        + MenuTabContentLayout.actionRowHeight

    var body: some View {
        VStack(spacing: 0) {
            consumptionBlock
            MenuSettingsSectionHeader()
            Grid(horizontalSpacing: 0, verticalSpacing: MenuTabContentLayout.rowSpacing) {
                ForEach(ClaudeRoute.all) { route in
                    mappingRow(route)
                }
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
            summary: model.gatewayClientUsage[.claude]
                ?? GatewayUsageSummary(
                    history: GatewayUsageHistory(),
                    client: .claude,
                    now: Date()
                )
        )
    }

    private var consumptionBlock: some View {
        MenuUsageStatsBlock(stats: consumption)
            .padding(.horizontal, MenuStatsBlockLayout.horizontalPadding)
    }

    private func mappingRow(_ route: ClaudeRoute) -> some View {
        GridRow {
            Text(route.displayName)
                .font(.system(size: 12, weight: .medium))
                .fixedSize()
                .frame(height: MenuTabContentLayout.rowHeight)
                .gridColumnAlignment(.leading)
            MenuMappingArrow()
            if model.modelOptions.isEmpty {
                MenuModelLoadingPlaceholder()
            } else {
                MenuModelStepper(
                    name: route.displayName,
                    options: routeOptions,
                    selection: Binding<MenuModelOption?>(
                        get: {
                            routeOptions.first { $0.id == model.optionID(for: route.id) }
                                ?? routeOptions.first { $0.mapping == nil }
                        },
                        set: { option in
                            Task { await onMapping(route.id, option?.mapping) }
                        }
                    ),
                    width: MenuTabContentLayout.mappingPickerWidth
                )
            }
        }
    }

    private var routeOptions: [MenuModelOption] {
        [MenuModelOption(id: "none", label: "Not assigned", mapping: nil)]
            + model.modelOptions.map { option in
                MenuModelOption(id: option.id, label: option.label, mapping: option.mapping)
            }
    }

    private var actionRow: some View {
        HStack {
            if model.hasPendingClaudeMappings || model.hasPendingClaudeCodeChanges {
                Text("Changes pending")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            MenuApplyButton(
                action: .claude(
                    model: model,
                    cancelTracking: cancelTracking,
                    onApply: onApplyClaude
                )
            )
        }
        .padding(.horizontal, MenuStatsBlockLayout.horizontalPadding)
        .frame(width: StatusMenuLayout.width, height: MenuTabContentLayout.actionRowHeight)
    }
}
