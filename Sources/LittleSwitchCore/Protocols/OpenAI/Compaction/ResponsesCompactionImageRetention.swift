import Foundation

enum ResponsesCompactionImageRetention {
    static func indices(in items: [[String: Any]]) throws -> Set<Int> {
        try Set(
            items.enumerated().compactMap { index, item in
                try ResponsesImageInputProjection.imageCount(in: WireJSONCompatibility.value(item)) > 0 ? index : nil
            })
    }
}

extension ResponsesCompactionPlan {
    /// Only images received by the gateway can be preserved; client-side omissions cannot be recovered.
    package func preservingUninspectedImages() throws -> Self {
        let required = retention.retaining(imageItemIndices)
        return Self(
            originalModel: originalModel,
            requestJSON: requestJSON,
            items: items,
            imageItemIndices: imageItemIndices,
            retention: retention,
            preservedStateIndices: preservedStateIndices,
            retainedStateIndices: retainedStateIndices.union(required),
            omittedIndices: omittedIndices.subtracting(required))
    }
}
