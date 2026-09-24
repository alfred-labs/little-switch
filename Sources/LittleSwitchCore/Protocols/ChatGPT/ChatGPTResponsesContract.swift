/// Adapter options not exposed as public keys by the generated Responses
/// request projection, plus a tolerated nonstandard provider error event.
/// All projected provider fields and event types use LittleSwitchWire directly.
enum ChatGPTResponsesContract {
    enum RequestField: String {
        case stream
        case store
    }

    enum CompatibilityEvent: String {
        case responseError = "response.error"
    }
}
