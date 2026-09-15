package struct ModelImageInputProbeDiagnostic: Equatable, Sendable {
    package let key: ModelImageInputKey
    package let result: ModelImageInputProbeResult

    package init(key: ModelImageInputKey, result: ModelImageInputProbeResult) {
        self.key = key
        self.result = result
    }
}
