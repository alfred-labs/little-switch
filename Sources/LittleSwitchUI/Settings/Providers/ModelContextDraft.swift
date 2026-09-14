import Foundation
import LittleSwitchCommon
import LittleSwitchCore

public struct ModelContextDraft: Equatable, Identifiable, Sendable {
    public let id: String
    public let detectedContextWindow: Int?
    public let allows1MOverride: Bool
    public var overrideText: String

    public init(model: DiscoveredModel) {
        id = model.id
        detectedContextWindow = model.detectedContextWindow
        allows1MOverride = model.allows1MContextOverride
        overrideText = model.contextWindowOverride.map(Self.format) ?? ""
        // A probe reporting less than 1M deactivates a saved 1M override:
        // the row starts Auto and the grayed switch cannot re-arm it.
        if !allows1MOverride, (try? parsedOverride()).map({ $0 >= 1_000_000 }) == true {
            overrideText = ""
        }
    }

    public func parsedOverride() throws -> Int? {
        try ContextWindowInput.parse(overrideText)
    }

    public var declares1MManually: Bool {
        get { (try? parsedOverride()) == 1_000_000 }
        set { overrideText = newValue ? "1M" : "" }
    }

    public var isValid: Bool {
        do {
            _ = try parsedOverride()
            return true
        } catch {
            return false
        }
    }

    public var detail: String {
        guard isValid else {
            return "Invalid context override"
        }
        let detected = detectedContextWindow.map(Self.format) ?? "Unknown"
        let effectiveContext = (try? parsedOverride()) ?? detectedContextWindow
        let effective = effectiveContext.map(Self.format) ?? "Unknown"
        let claude = effectiveContext.map { $0 >= 1_000_000 } == true ? "200K or 1M" : "200K"
        return "Detected \(detected) · Effective \(effective) · Claude \(claude)"
    }

    var capacityText: String {
        guard isValid else { return "Invalid override" }
        return ((try? parsedOverride()) ?? detectedContextWindow).map(Self.format) ?? "Unknown"
    }

    /// Only a differing manual value needs a second line in the compact table.
    var capacityNote: String? {
        guard isValid, let override = try? parsedOverride(), override != detectedContextWindow else { return nil }
        return detectedContextWindow.map { "Detected \(Self.format($0))" } ?? "Manual override"
    }

    public static func contextOverrides(from drafts: [ModelContextDraft]) throws -> [String: Int] {
        try drafts.reduce(into: [:]) { result, draft in
            if let value = try draft.parsedOverride() {
                result[draft.id] = value
            }
        }
    }

    public static func format(_ tokens: Int) -> String {
        if tokens.isMultiple(of: 1_000_000) {
            return "\(tokens / 1_000_000)M"
        }
        if tokens.isMultiple(of: 1_000) {
            return "\(tokens / 1_000)K"
        }
        return String(tokens)
    }
}
