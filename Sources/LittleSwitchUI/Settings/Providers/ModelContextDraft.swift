import Foundation
import LittleSwitchCommon
import LittleSwitchCore

public struct ModelContextDraft: Equatable, Identifiable, Sendable {
    enum Claude1MState: Equatable, Sendable {
        case automatic
        case unavailable
        case manual
    }

    public let id: String
    public let detectedContextWindow: Int?
    let claude1MState: Claude1MState
    public var overrideText: String

    public var allows1MOverride: Bool { claude1MState == .manual }

    public init(model: DiscoveredModel) {
        id = model.id
        detectedContextWindow = model.detectedContextWindow
        if model.allows1MContextOverride {
            claude1MState = .manual
            overrideText = model.contextWindowOverride.map(Self.format) ?? ""
        } else {
            claude1MState = model.supports1MContext ? .automatic : .unavailable
            overrideText = ""
        }
    }

    public func parsedOverride() throws -> Int? {
        guard allows1MOverride else { return nil }
        return try ContextWindowInput.parse(overrideText)
    }

    public var declares1MManually: Bool {
        get { (try? parsedOverride()).map { $0 >= 1_000_000 } ?? false }
        set { overrideText = allows1MOverride && newValue ? "1M" : "" }
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
            return L10n.string("Invalid context override")
        }
        let detected = detectedContextWindow.map(Self.format) ?? L10n.string("Unknown")
        let effectiveContext = detectedContextWindow ?? (try? parsedOverride())
        let effective = effectiveContext.map(Self.format) ?? L10n.string("Unknown")
        let claude =
            effectiveContext.map { $0 >= 1_000_000 } == true
            ? L10n.string("200K or 1M")
            : L10n.string("200K")
        return L10n.string("Detected \(detected) · Effective \(effective) · Claude \(claude)")
    }

    var capacityText: String {
        guard isValid else { return L10n.string("Invalid override") }
        return detectedContextWindow.map { $0.formatted(.number) }
            ?? L10n.string("Not reported")
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
            return L10n.string("\(tokens / 1_000_000)M")
        }
        if tokens.isMultiple(of: 1_000) {
            return L10n.string("\(tokens / 1_000)K")
        }
        return String(tokens)
    }
}
