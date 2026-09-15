enum ModelImageProbeColor: String, CaseIterable, Sendable {
    case red, green, blue, yellow, black, white

    var rgb: [UInt8] {
        switch self {
        case .red: [255, 0, 0]
        case .green: [0, 255, 0]
        case .blue: [0, 0, 255]
        case .yellow: [255, 255, 0]
        case .black: [0, 0, 0]
        case .white: [255, 255, 255]
        }
    }
}
