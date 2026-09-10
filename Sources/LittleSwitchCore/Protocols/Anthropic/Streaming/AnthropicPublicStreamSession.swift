import Foundation

package struct AnthropicPublicStreamSession: Sendable {
    enum TerminalState: Sendable {
        case open
        case completed
        case failed
    }

    private enum ProviderBlockDisposition: Sendable {
        case emitted(publicIndex: Int)
        case buffered
        case deferredAfterSearch
        case suppressed
    }

    struct PendingSearch: Sendable {
        let toolUseID: String
        let query: String
    }

    private let originalModel: String
    package let privateToolName: String?
    var terminalState = TerminalState.open
    var started = false
    var providerTurnActive = false
    private var providerMessageDeltaSeen = false
    private var providerBlocks: [Int: ProviderBlockDisposition] = [:]
    var bufferedEvents: [AnthropicProviderStreamEvent] = []
    var postSearchEvents: [AnthropicProviderStreamEvent] = []
    private var bufferingTurn = false
    private var turnContainsPrivateSearch = false
    private var nextPublicIndex = 0
    var pendingSearch: PendingSearch?
    private var usedSearchIDs: Set<String> = []
    var successfulSearchCount = 0

    package init(originalModel: String, privateToolName: String? = "web_search") {
        self.originalModel = originalModel
        self.privateToolName = privateToolName
    }

    package mutating func start(
        from event: AnthropicProviderStreamEvent
    ) throws -> [Data] {
        guard terminalState == .open,
            !started,
            !originalModel.isEmpty,
            case .messageStart(let messageJSON) = event
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        let providerMessage = try publicStreamObject(messageJSON)
        guard let messageID = providerMessage["id"] as? String,
            !messageID.isEmpty,
            let usage = providerMessage["usage"] as? [String: Any]
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        let inputTokens = try publicTokenCount(usage["input_tokens"])

        let frame = try publicStreamFrame(
            name: "message_start",
            payload: [
                "type": "message_start",
                "message": [
                    "id": messageID,
                    "type": "message",
                    "role": "assistant",
                    "model": originalModel,
                    "content": [],
                    "stop_reason": NSNull(),
                    "stop_sequence": NSNull(),
                    "usage": publicUsage(
                        inputTokens: inputTokens,
                        outputTokens: 0,
                        webSearchRequests: 0
                    ),
                ],
            ]
        )
        started = true
        beginProviderTurn()
        return [frame]
    }

    package mutating func consumePublic(
        _ event: AnthropicProviderStreamEvent
    ) throws -> [Data] {
        guard terminalState == .open, started else {
            throw AnthropicWebSearch.Error.invalidMessage
        }

        switch event {
        case .messageStart(let messageJSON):
            guard !providerTurnActive,
                pendingSearch == nil,
                (try publicStreamObject(messageJSON)["id"] as? String)?.isEmpty == false
            else {
                throw AnthropicWebSearch.Error.invalidMessage
            }
            beginProviderTurn()
            return []
        // swiftlint:disable:next pattern_matching_keywords
        case .contentStart(let index, let blockJSON):
            return try consumeContentStart(index: index, blockJSON: blockJSON)
        // swiftlint:disable:next pattern_matching_keywords
        case .contentDelta(let index, let deltaJSON):
            return try consumeContentDelta(index: index, deltaJSON: deltaJSON)
        case .contentStop(let index):
            return try consumeContentStop(index: index)
        // swiftlint:disable:next pattern_matching_keywords
        case .messageDelta(let deltaJSON, let usageJSON):
            guard providerTurnActive,
                providerBlocks.isEmpty
            else {
                throw AnthropicWebSearch.Error.invalidMessage
            }
            _ = try publicStreamObject(deltaJSON)
            _ = try publicStreamObject(usageJSON)
            providerMessageDeltaSeen = true
            return []
        case .messageStop:
            guard providerTurnActive,
                providerMessageDeltaSeen,
                providerBlocks.isEmpty
            else {
                throw AnthropicWebSearch.Error.invalidMessage
            }
            let frames = try flushBufferedTurn(
                suppressOrdinaryTools: turnContainsPrivateSearch
            )
            providerTurnActive = false
            providerMessageDeltaSeen = false
            bufferingTurn = false
            if !turnContainsPrivateSearch {
                postSearchEvents.removeAll(keepingCapacity: true)
            }
            return frames
        case .ping:
            return [
                try publicStreamFrame(
                    name: "ping",
                    payload: ["type": "ping"]
                )
            ]
        }
    }

    package mutating func beginSearch(
        toolUseID: String,
        query: String
    ) throws -> [Data] {
        guard terminalState == .open,
            started,
            !providerTurnActive,
            pendingSearch == nil,
            !toolUseID.isEmpty,
            !usedSearchIDs.contains(toolUseID)
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }

        let index = allocatePublicIndex()
        let queryData = try publicStreamData(["query": query])
        // JSONSerialization output is always valid UTF-8.
        // swiftlint:disable:next optional_data_string_conversion
        let queryJSON = String(decoding: queryData, as: UTF8.self)
        let frames = [
            try publicStreamFrame(
                name: "content_block_start",
                payload: [
                    "type": "content_block_start",
                    "index": index,
                    "content_block": [
                        "type": "server_tool_use",
                        "id": toolUseID,
                        "name": "web_search",
                        "input": [:],
                        "caller": ["type": "direct"],
                    ],
                ]
            ),
            try publicStreamFrame(
                name: "content_block_delta",
                payload: [
                    "type": "content_block_delta",
                    "index": index,
                    "delta": [
                        "type": "input_json_delta",
                        "partial_json": queryJSON,
                    ],
                ]
            ),
            try contentStopFrame(index: index),
        ]
        usedSearchIDs.insert(toolUseID)
        pendingSearch = PendingSearch(toolUseID: toolUseID, query: query)
        return frames
    }

}

extension AnthropicPublicStreamSession {
    private mutating func beginProviderTurn() {
        providerTurnActive = true
        providerMessageDeltaSeen = false
        providerBlocks.removeAll(keepingCapacity: true)
        bufferedEvents.removeAll(keepingCapacity: true)
        postSearchEvents.removeAll(keepingCapacity: true)
        bufferingTurn = false
        turnContainsPrivateSearch = false
    }

    private mutating func consumeContentStart(
        index: Int,
        blockJSON: Data
    ) throws -> [Data] {
        guard providerTurnActive,
            !providerMessageDeltaSeen,
            index >= 0,
            providerBlocks[index] == nil
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        let providerBlock = try publicStreamObject(blockJSON)
        guard let type = providerBlock["type"] as? String else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        guard let block = try AnthropicPublicSanitizer.block(providerBlock) else {
            providerBlocks[index] = .suppressed
            return []
        }

        let privateSearch = AnthropicWebSearch.isPrivateSearchBlock(block, privateToolName: privateToolName)
        let ordinaryTool = type == "tool_use" && !privateSearch
        if privateSearch {
            turnContainsPrivateSearch = true
        }

        let publicBlockJSON = try publicStreamData(block)
        let event = AnthropicProviderStreamEvent.contentStart(
            index: index,
            blockJSON: publicBlockJSON
        )
        if privateSearch {
            providerBlocks[index] = .suppressed
            return []
        }
        if turnContainsPrivateSearch {
            postSearchEvents.append(event)
            providerBlocks[index] = .deferredAfterSearch
            return []
        }
        if bufferingTurn || ordinaryTool {
            bufferingTurn = true
            bufferedEvents.append(event)
            providerBlocks[index] = .buffered
            return []
        }

        let emitted = try emitContentStart(block, type: type)
        providerBlocks[index] = .emitted(publicIndex: emitted.publicIndex)
        return emitted.frames
    }

    private mutating func consumeContentDelta(
        index: Int,
        deltaJSON: Data
    ) throws -> [Data] {
        guard providerTurnActive,
            !providerMessageDeltaSeen,
            let disposition = providerBlocks[index]
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        let providerDelta = try publicStreamObject(deltaJSON)
        let publicDelta = try AnthropicPublicSanitizer.delta(providerDelta)
        guard let publicDelta else {
            return []
        }
        let publicDeltaJSON = try publicStreamData(publicDelta)
        let event = AnthropicProviderStreamEvent.contentDelta(
            index: index,
            deltaJSON: publicDeltaJSON
        )
        switch disposition {
        case .emitted(let publicIndex):
            return [try contentDeltaFrame(index: publicIndex, deltaJSON: publicDeltaJSON)]
        case .buffered:
            bufferedEvents.append(event)
            return []
        case .deferredAfterSearch:
            postSearchEvents.append(event)
            return []
        case .suppressed:
            return []
        }
    }

    private mutating func consumeContentStop(index: Int) throws -> [Data] {
        guard providerTurnActive,
            !providerMessageDeltaSeen,
            let disposition = providerBlocks.removeValue(forKey: index)
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        let event = AnthropicProviderStreamEvent.contentStop(index: index)
        switch disposition {
        case .emitted(let publicIndex):
            return [try contentStopFrame(index: publicIndex)]
        case .buffered:
            bufferedEvents.append(event)
            return []
        case .deferredAfterSearch:
            postSearchEvents.append(event)
            return []
        case .suppressed:
            return []
        }
    }

    private mutating func flushBufferedTurn(
        suppressOrdinaryTools: Bool
    ) throws -> [Data] {
        guard !bufferedEvents.isEmpty else {
            return []
        }
        let events = bufferedEvents
        bufferedEvents.removeAll(keepingCapacity: true)
        return try replayBufferedEvents(
            events,
            suppressOrdinaryTools: suppressOrdinaryTools
        )
    }

    mutating func flushPostSearchTurn() throws -> [Data] {
        let events = postSearchEvents
        postSearchEvents.removeAll(keepingCapacity: true)
        defer { turnContainsPrivateSearch = false }
        return try replayBufferedEvents(events, suppressOrdinaryTools: true)
    }

    private mutating func replayBufferedEvents(
        _ events: [AnthropicProviderStreamEvent],
        suppressOrdinaryTools: Bool
    ) throws -> [Data] {
        var frames: [Data] = []
        var replayBlocks: [Int: ProviderBlockDisposition] = [:]
        for event in events {
            switch event {
            // swiftlint:disable:next pattern_matching_keywords
            case .contentStart(let index, let blockJSON):
                let block = try publicStreamObject(blockJSON)
                guard let type = block["type"] as? String else {
                    throw AnthropicWebSearch.Error.invalidMessage
                }
                let privateSearch = AnthropicWebSearch.isPrivateSearchBlock(block, privateToolName: privateToolName)
                let ordinaryTool = type == "tool_use"
                if privateSearch || ordinaryTool && suppressOrdinaryTools {
                    replayBlocks[index] = .suppressed
                } else {
                    guard let publicBlock = try AnthropicPublicSanitizer.block(block) else {
                        replayBlocks[index] = .suppressed
                        continue
                    }
                    let emitted = try emitContentStart(publicBlock, type: type)
                    replayBlocks[index] = .emitted(publicIndex: emitted.publicIndex)
                    frames += emitted.frames
                }
            // swiftlint:disable:next pattern_matching_keywords
            case .contentDelta(let index, let deltaJSON):
                guard let disposition = replayBlocks[index] else {
                    throw AnthropicWebSearch.Error.invalidMessage
                }
                if case .emitted(let publicIndex) = disposition {
                    frames.append(
                        try contentDeltaFrame(index: publicIndex, deltaJSON: deltaJSON)
                    )
                }
            case .contentStop(let index):
                guard let disposition = replayBlocks.removeValue(forKey: index) else {
                    throw AnthropicWebSearch.Error.invalidMessage
                }
                if case .emitted(let publicIndex) = disposition {
                    frames.append(try contentStopFrame(index: publicIndex))
                }
            default:
                throw AnthropicWebSearch.Error.invalidMessage
            }
        }
        guard replayBlocks.isEmpty else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        return frames
    }

    private mutating func emitContentStart(
        _ publicBlock: [String: Any],
        type: String
    ) throws -> (frames: [Data], publicIndex: Int) {
        var block = publicBlock
        let index = allocatePublicIndex()
        var syntheticDeltas: [[String: Any]] = []

        switch type {
        case "text":
            // Every caller passes a block validated by AnthropicPublicSanitizer.
            // swiftlint:disable:next force_cast
            let text = block["text"] as! String
            block["text"] = ""
            if !text.isEmpty {
                syntheticDeltas.append(["type": "text_delta", "text": text])
            }
        case "thinking":
            // Every caller passes a block validated by AnthropicPublicSanitizer.
            // swiftlint:disable:next force_cast
            let thinking = block["thinking"] as! String
            let signature = block["signature"] as? String
            block["thinking"] = ""
            if block["signature"] != nil {
                block["signature"] = ""
            }
            if !thinking.isEmpty {
                syntheticDeltas.append([
                    "type": "thinking_delta",
                    "thinking": thinking,
                ])
            }
            if let signature, !signature.isEmpty {
                syntheticDeltas.append([
                    "type": "signature_delta",
                    "signature": signature,
                ])
            }
        default:
            break
        }

        var frames = [
            try publicStreamFrame(
                name: "content_block_start",
                payload: [
                    "type": "content_block_start",
                    "index": index,
                    "content_block": block,
                ]
            )
        ]
        for delta in syntheticDeltas {
            frames.append(
                try publicStreamFrame(
                    name: "content_block_delta",
                    payload: [
                        "type": "content_block_delta",
                        "index": index,
                        "delta": delta,
                    ]
                )
            )
        }
        return (frames, index)
    }

    mutating func allocatePublicIndex() -> Int {
        defer { nextPublicIndex += 1 }
        return nextPublicIndex
    }
}
