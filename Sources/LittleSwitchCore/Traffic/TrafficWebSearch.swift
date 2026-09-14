import Foundation
import LittleSwitchCommon
import LittleSwitchSearch

extension TrafficWebSearch {
    package static func make(
        configuration: WebSearchConfiguration,
        query: String,
        startedAt: Date,
        resultCount: Int?,
        error: Swift.Error?
    ) -> TrafficWebSearch {
        TrafficWebSearch(
            provider: configuration.provider.rawValue,
            query: query,
            startedAt: startedAt,
            finishedAt: Date(),
            resultCount: resultCount,
            failure: error.map {
                TrafficFailure(kind: "web-search", message: String(describing: $0))
            }
        )
    }
}
