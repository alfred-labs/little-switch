extension LittleSwitchApplicationDelegate {
    func pollRequestCount() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled, let coordinator else {
                return
            }
            let update = await GatewayActivityPollingUpdate.load(
                from: coordinator,
                usageHistory: usageHistoryStore
            )
            update.apply(to: model)
            statusItemController?.refreshGatewayActivity()
            statusItemController?.refreshIcon()
        }
    }
}
