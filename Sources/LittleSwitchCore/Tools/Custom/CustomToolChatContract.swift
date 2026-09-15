/// The generated Chat completion, choice, message and tool-delta projections
/// keep their Key enums private. This adapter needs partial JSON to retain
/// unknown fields and assemble call fragments without requiring a complete DTO.
enum CustomToolChatContract {
    enum CompletionKey: String {
        case choices
    }

    enum ChoiceKey: String {
        case index
        case delta
        case message
        case finishReason = "finish_reason"
    }

    enum MessageKey: String {
        case toolCalls = "tool_calls"
    }

    enum CallKey: String {
        case index
        case id
        case type
        case function
        case custom
    }

    enum PayloadKey: String {
        case name
        case arguments
        case input
    }
}
