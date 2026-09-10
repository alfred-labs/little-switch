@MainActor
enum ApplicationStartupFailurePresentation {
    static func apply(
        snapshot: CoordinatorSnapshot?,
        message: String,
        to model: AppModel,
        synchronizeMenu: @MainActor () -> Void
    ) {
        if let snapshot {
            model.apply(snapshot)
        }
        model.updateGatewayActivity(.unavailable)
        model.isBusy = false
        model.errorMessage = message
        synchronizeMenu()
    }
}
