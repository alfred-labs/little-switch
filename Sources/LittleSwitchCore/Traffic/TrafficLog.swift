import Foundation
import HTTPTypes
import LittleSwitchCommon
import NIOHTTP1

public protocol TrafficRecording: Sendable {
    func record(eventID: UUID, action: TrafficAction)
}

public struct NoopTrafficRecorder: TrafficRecording {
    public init() {}

    public func record(eventID: UUID, action: TrafficAction) {
        _ = eventID
        _ = action
    }
}

public enum TrafficRedactor {
    public static let mask = "<redacted>"
    public static let invalidURL = "<invalid-url>"

    public static func headers(_ fields: HTTPFields) -> [TrafficHeader] {
        fields.map { field in
            header(name: field.name.rawName, value: field.value)
        }
    }

    public static func headers(_ fields: HTTPHeaders) -> [TrafficHeader] {
        fields.map { name, value in
            header(name: name, value: value)
        }
    }

    public static func url(_ value: String) -> String {
        guard var components = URLComponents(string: value),
            components.scheme != nil,
            components.host?.isEmpty == false
        else {
            return invalidURL
        }
        components.user = nil
        components.password = nil
        components.fragment = nil
        components.queryItems = components.queryItems?.map { item in
            URLQueryItem(
                name: item.name,
                value: isSensitive(item.name) ? mask : item.value
            )
        }
        return components.description
    }

    private static func header(name: String, value: String) -> TrafficHeader {
        TrafficHeader(name: name, value: isSensitive(name) ? mask : value)
    }

    private static func isSensitive(_ name: String) -> Bool {
        let normalized = name.lowercased().filter(\.isLetter)
        return normalized.contains("authorization")
            || normalized.contains("apikey")
            || normalized.contains("token")
            || normalized.contains("secret")
            || normalized.contains("password")
            || normalized.contains("credential")
            || normalized.contains("signature")
            || normalized == "cookie"
            || normalized == "setcookie"
    }
}
