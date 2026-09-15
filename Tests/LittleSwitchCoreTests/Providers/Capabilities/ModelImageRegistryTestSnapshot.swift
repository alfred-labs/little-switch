import LittleSwitchCommon

@testable import LittleSwitchCore

extension ModelImageInputRegistry {
    /// Inspection of retained evidence belongs in the test target, not the product API.
    func observations() -> [ModelImageInputObservation] {
        ModelImageInputObservationMerge.merge(
            existing: Array(evidence.values), incoming: [], validKeys: Set(evidence.keys))
    }
}

actor ImageProbeDiagnosticRecorder {
    private(set) var latest: [ModelImageInputKey: ModelImageInputProbeDiagnostic] = [:]
    func record(_ diagnostic: ModelImageInputProbeDiagnostic) { latest[diagnostic.key] = diagnostic }
}
