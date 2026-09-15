/// Adapter-owned summary tool, quoted transcript and portable checkpoint fields.
/// Provider envelopes and message fields use their generated LittleSwitchWire keys.
enum ResponsesCompactionContract {
    enum Selection: String {
        case summary
        case retainedIDs = "retain_item_ids"
    }

    enum Payload: String {
        case type, version, summary, retained
        case encryptedContent = "encrypted_content"
    }

    enum Transcript: String {
        case context, ref, type, item
        case imageIndex = "image_index"
    }

    enum Schema: String {
        case type, properties, required, items
        case additionalProperties
    }

    /// Function tools and non-routing request options are opaque generated projections.
    enum Tool: String {
        case type, name, strict, description, parameters
    }

    enum Request: String {
        case instructions, stream, store
        case parallelToolCalls = "parallel_tool_calls"
    }

    enum Kind: String {
        case compaction
        case function
        case object
        case owned = "little_switch_compaction"
    }
}
