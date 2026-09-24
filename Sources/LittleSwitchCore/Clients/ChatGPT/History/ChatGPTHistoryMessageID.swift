import Foundation

enum ChatGPTHistoryMessageID {
    static func make(excluding occupied: Set<String>, startingWith candidate: UUID = UUID()) -> String {
        var identifier = candidate.uuidString.lowercased()
        while occupied.contains(identifier) {
            identifier = UUID().uuidString.lowercased()
        }
        return identifier
    }
}
