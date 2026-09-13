import Foundation
import LittleSwitchWire

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
        guard let messageID = providerMessage[AnthropicMessage.Key.id.rawValue]?.string,
            !messageID.isEmpty,
            let usage = providerMessage[AnthropicMessage.Key.usage.rawValue]?.anthropicObject
        else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        let inputTokens = try publicTokenCount(usage[AnthropicUsageFields.Key.inputTokens.rawValue])

        let frame = try publicStreamFrame(
            name: AnthropicMessageStartEventType.messageStart.rawValue,
            payload: AnthropicMessageStartEvent(
                message: publicMessage(
                    AnthropicMessage(
                        content: [],
                        id: messageID,
                        stopReason: .null,
                        stopSequence: .null,
                        usage: publicUsage(inputTokens: inputTokens, outputTokens: 0, webSearchRequests: 0)
                    ),
                    model: originalModel
                ),
                type: .messageStart
            ).wireJSON()
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
                (try publicStreamObject(messageJSON)[AnthropicMessage.Key.id.rawValue]?.string)?.isEmpty == false
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
        let call = AnthropicServerToolUseBlock(
            caller: .value(try AnthropicDirectCaller(type: .direct).wireJSON()),
            id: toolUseID,
            input: AnthropicPrivateSearchInput.value(query: query),
            name: .known(.webSearch),
            type: .serverToolUse
        )
        let frames =
            try publicContentStartFrames(.serverToolUse(call), index: index, includeToolInput: true)
            + [contentStopFrame(index: index)]
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
        guard let type = providerBlock[AnthropicToolUseBlock.Key.type.rawValue]?.string else {
            throw AnthropicWebSearch.Error.invalidMessage
        }
        guard let block = try AnthropicPublicSanitizer.block(providerBlock) else {
            providerBlocks[index] = .suppressed
            return []
        }

        let privateSearch = AnthropicWebSearch.isPrivateSearchBlock(block, privateToolName: privateToolName)
        let ordinaryTool = type == AnthropicToolUseBlockType.toolUse.rawValue && !privateSearch
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

        let emitted = try emitContentStart(block)
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
                guard let type = block[AnthropicToolUseBlock.Key.type.rawValue]?.string else {
                    throw AnthropicWebSearch.Error.invalidMessage
                }
                let privateSearch = AnthropicWebSearch.isPrivateSearchBlock(block, privateToolName: privateToolName)
                let ordinaryTool = type == AnthropicToolUseBlockType.toolUse.rawValue
                if privateSearch || ordinaryTool && suppressOrdinaryTools {
                    replayBlocks[index] = .suppressed
                } else {
                    guard let publicBlock = try AnthropicPublicSanitizer.block(block) else {
                        replayBlocks[index] = .suppressed
                        continue
                    }
                    let emitted = try emitContentStart(publicBlock)
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
        _ publicBlock: [String: JSONValue]
    ) throws -> (frames: [Data], publicIndex: Int) {
        let index = allocatePublicIndex()
        let block = try anthropicDecode(AnthropicContentBlock.self, from: anthropicJSON(publicBlock))
        return (try publicContentStartFrames(block, index: index), index)
    }

    mutating func allocatePublicIndex() -> Int {
        defer { nextPublicIndex += 1 }
        return nextPublicIndex
    }
}
