import LittleSwitchWire

/// The two tool dialects share Core's streaming identity and completion rules.
/// Their fields still come from their respective generated SDK records.
protocol ResponsesToolInputWireEvent: Sendable {
    var outputIndex: JSONNumber { get }
    var itemId: String { get }
    var callId: JSONPresence<String> { get }
    var name: JSONPresence<String> { get }
    var inputText: String { get }
}

extension OpenAIFunctionArgumentsDelta: ResponsesToolInputWireEvent {
    var inputText: String { delta }
}

extension OpenAIFunctionArgumentsDone: ResponsesToolInputWireEvent {
    var inputText: String { arguments }
}

extension OpenAICustomInputDelta: ResponsesToolInputWireEvent {
    var inputText: String { delta }
}

extension OpenAICustomInputDone: ResponsesToolInputWireEvent {
    var inputText: String { input }
}
