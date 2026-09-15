import Foundation

/// Derived evidence is recoverable. One damaged entry must not hide provider settings.
package enum ModelImageInputObservationDecoding {
    package static func decode<Key: CodingKey>(
        from values: KeyedDecodingContainer<Key>, forKey key: Key
    ) -> [ModelImageInputObservation] {
        guard var entries = try? values.nestedUnkeyedContainer(forKey: key) else { return [] }
        var observations: [ModelImageInputObservation] = []
        while !entries.isAtEnd {
            guard let decoder = try? entries.superDecoder() else { break }
            if let observation = try? ModelImageInputObservation(from: decoder) {
                observations.append(observation)
            }
        }
        return observations
    }
}
