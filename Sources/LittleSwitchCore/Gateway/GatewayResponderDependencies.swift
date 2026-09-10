package struct GatewayResponderDependencies: Sendable {
    let serializer: any GatewaySerializing
    let snapshotCapturer: any GatewayRoutingSnapshotCapturing
    let admitter: any GatewayAdmitting
    let projector: any GatewayWebSearchProjecting
    let tokenEstimator: any GatewayTokenEstimating
    let initialUsageResolver: any AnthropicInitialUsageResolving
    let retryRequestBuilder: any GatewayRetryRequestBuilding

    package init(
        serializer: any GatewaySerializing = LiveGatewaySerializer(),
        snapshotCapturer: any GatewayRoutingSnapshotCapturing = LiveGatewayRoutingSnapshotCapturer(),
        admitter: any GatewayAdmitting = LiveGatewayAdmitter(),
        projector: any GatewayWebSearchProjecting = LiveGatewayWebSearchProjector(),
        tokenEstimator: any GatewayTokenEstimating = LiveGatewayTokenEstimator(),
        initialUsageResolver: (any AnthropicInitialUsageResolving)? = nil,
        retryRequestBuilder: any GatewayRetryRequestBuilding = LiveGatewayRetryRequestBuilder()
    ) {
        self.serializer = serializer
        self.snapshotCapturer = snapshotCapturer
        self.admitter = admitter
        self.projector = projector
        self.tokenEstimator = tokenEstimator
        self.initialUsageResolver =
            initialUsageResolver
            ?? LiveAnthropicInitialUsageResolver(tokenEstimator: tokenEstimator)
        self.retryRequestBuilder = retryRequestBuilder
    }
}
