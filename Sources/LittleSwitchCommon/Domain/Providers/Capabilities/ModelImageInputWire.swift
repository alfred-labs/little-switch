/// Image evidence is specific to the API actually used for inference.
public enum ModelImageInputWire: String, Codable, Hashable, Sendable {
    case responses
    case chatCompletions
}
