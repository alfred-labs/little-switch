extension ApplicationCoordinator {
    public func gatewayActivity() async -> GatewayActivitySnapshot {
        var stableActivity: GatewayActivitySnapshot?
        repeat {
            let generation = gatewayLifecycleGeneration
            if gatewayActivityStartingCount > 0 || gatewayStartup != nil {
                stableActivity = .starting
            } else if let state = gatewayState, let server = gatewayServer {
                let poolSnapshot = await state.requestPoolSnapshot()
                let isRunning = await server.isRunning
                // A lifecycle change that lands between these awaits and the
                // reads' use is caught by the generation guard: the snapshot
                // re-loops instead of answering from a superseded server.
                if generation == gatewayLifecycleGeneration, gatewayState === state {
                    stableActivity = isRunning ? .running(poolSnapshot) : .unavailable
                }
            } else {
                stableActivity = .unavailable
            }
        } while stableActivity == nil
        return stableActivity.unsafelyUnwrapped
    }
}
