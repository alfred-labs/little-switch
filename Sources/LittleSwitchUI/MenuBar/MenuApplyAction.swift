import SwiftUI

/// Pointer and keyboard activation share the same live availability gate
/// and the existing coordinator callbacks.
@MainActor
struct MenuApplyAction {
    private let enabled: @MainActor () -> Bool
    private let perform: @MainActor () -> Void

    init(
        isEnabled: @autoclosure @escaping @MainActor () -> Bool,
        perform: @escaping @MainActor () -> Void
    ) {
        enabled = isEnabled
        self.perform = perform
    }

    var isEnabled: Bool { enabled() }

    func callAsFunction() {
        guard isEnabled else {
            return
        }
        perform()
    }

    static func claude(
        model: AppModel,
        cancelTracking: @escaping @MainActor () -> Void,
        onApply:
            @escaping @MainActor (
                AppModel.ClaudePrimaryAction?,
                AppModel.ClaudeCodePrimaryAction?
            ) async -> Void
    ) -> Self {
        Self(isEnabled: model.canApplyClaudeProducts && !model.isBusy) {
            let desktopAction =
                model.canPerformClaudePrimaryAction ? model.claudePrimaryAction : nil
            let codeAction =
                model.canPerformClaudeCodePrimaryAction ? model.claudeCodePrimaryAction : nil
            // A confirmation alert must run after menu tracking ends.
            cancelTracking()
            Task { await onApply(desktopAction, codeAction) }
        }
    }

    static func codex(
        model: AppModel,
        onApply: @escaping @MainActor () async -> Void
    ) -> Self {
        Self(isEnabled: model.hasPendingCodexChanges && !model.isBusy && !model.hasUnavailableCodexAutoReviewModel) {
            Task { await onApply() }
        }
    }
}
