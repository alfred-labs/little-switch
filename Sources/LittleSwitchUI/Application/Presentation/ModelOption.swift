import Foundation
import LittleSwitchCommon

public struct ModelOption: Hashable, Identifiable, Sendable {
    public var providerID: UUID
    public var providerName: String
    public var modelID: String

    public var id: String {
        "\(providerID.uuidString)|\(modelID)"
    }

    public var label: String {
        "\(providerName)/\(modelID)"
    }

    public var mapping: ModelMapping {
        ModelMapping(providerID: providerID, modelID: modelID)
    }
}
