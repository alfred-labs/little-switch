import Foundation

extension GatewayResponder {
    package func recordWebSearch(eventID: UUID, search: TrafficWebSearch) {
        trafficRecorder.record(eventID: eventID, action: .webSearch(search))
    }
}
