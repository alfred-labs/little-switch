import Foundation

private struct ResponsesCompactionToolGroup: Sendable {
    let call: Int
    let family: String
    var result: Int?
}

struct ResponsesCompactionRetention: Sendable {
    private let dependencies: ResponsesCompactionDependencies
    private let forced: Set<Int>

    init(items: [[String: Any]], preservedStateIndices: Set<Int>) throws {
        var groups: [ResponsesCompactionToolGroup] = []
        var callIDs: [String: Int] = [:]
        var forced = Set<Int>()
        var latestAssistantActivity = -1
        for (index, item) in items.enumerated() {
            let kind = try ResponsesCompactionJSON.kind(item, error: .invalidRequest)
            let assistantActivity = ResponsesCompactionDependencies.isAssistantOutput(item, kind: kind)
            if assistantActivity && !preservedStateIndices.contains(index) {
                latestAssistantActivity = index
            }
            switch kind {
            case "function_call", "custom_tool_call", "tool_search_call":
                guard let callID = item["call_id"] as? String,
                    ResponsesCompactionJSON.nonempty(callID) != nil, callIDs[callID] == nil
                else {
                    throw ResponsesCompactionError.invalidRequest
                }
                callIDs[callID] = groups.count
                groups.append(ResponsesCompactionToolGroup(call: index, family: kind))
                if kind == "tool_search_call" { forced.insert(index) }
            case "function_call_output", "custom_tool_call_output", "tool_search_output":
                guard let callID = item["call_id"] as? String, ResponsesCompactionJSON.nonempty(callID) != nil else {
                    guard kind == "function_call_output", ResponsesCompactionJSON.nonempty(item["name"]) != nil else {
                        throw ResponsesCompactionError.invalidRequest
                    }
                    forced.insert(index)
                    continue
                }
                let family = kind == "tool_search_output" ? "tool_search_call" : String(kind.dropLast("_output".count))
                guard let groupIndex = callIDs[callID], groups[groupIndex].result == nil,
                    groups[groupIndex].family == family
                else { throw ResponsesCompactionError.invalidRequest }
                groups[groupIndex].result = index
                if kind == "tool_search_output" { forced.insert(index) }
            default:
                break
            }
        }
        for group in groups where group.result.map({ $0 >= latestAssistantActivity }) ?? true {
            forced.insert(group.call)
            if let result = group.result { forced.insert(result) }
        }
        dependencies = try ResponsesCompactionDependencies(
            items: items,
            toolPairs: groups.compactMap { group in group.result.map { (group.call, $0) } }
        )
        self.forced = forced
    }

    func retaining(_ selected: Set<Int>) -> Set<Int> {
        dependencies.retaining(selected.union(forced))
    }
}
