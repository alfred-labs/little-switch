import Foundation
import LittleSwitchCommon

enum StoredProviderValidation {
    static func validate(_ providers: [Provider]) throws {
        var identifiers = Set<UUID>()
        for provider in providers {
            guard identifiers.insert(provider.id).inserted else {
                throw ConfigurationStore.Error.duplicateProviderID(provider.id)
            }
            guard Provider.maximumParallelRequestsRange.contains(provider.maximumParallelRequests) else {
                throw ConfigurationStore.Error.invalidMaximumParallelRequests(
                    providerID: provider.id, value: provider.maximumParallelRequests)
            }
        }
    }
}
