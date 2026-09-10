package protocol GatewayStartupObserving: Sendable {
    func joinedStartup() async
    func readyToPublishStartup() async
    func waitingForAbandonedStartupCleanup() async
    func cancellingStartupWaiter() async
    func cancelledStartupWaiter() async
    func stoppingAbandonedStartup() async
}

package struct LiveGatewayStartupObserver: GatewayStartupObserving {
    package init() {}

    package func joinedStartup() async {}

    package func readyToPublishStartup() async {}

    package func waitingForAbandonedStartupCleanup() async {}

    package func cancellingStartupWaiter() async {}

    package func cancelledStartupWaiter() async {}

    package func stoppingAbandonedStartup() async {}
}
