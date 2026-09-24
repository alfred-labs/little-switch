/// Fields and discriminants of ChatGPT's native desktop backend, which is not
/// described by the official provider SDK. Unknown native fields remain opaque.
enum ChatGPTNativeContract {
    enum CatalogField: String {
        case models
        case versions
        case categories
        case slug
        case title
        case description
        case enabledTools = "enabled_tools"
        case configurableThinkingEffort = "configurable_thinking_effort"
        case reasoningType = "reasoning_type"
        case id
        case displayText = "display_text"
        case slugs
        case intelligencePresets = "intelligence_presets"
        case modelSlug = "model_slug"
        case selectedDisplayTitle = "selected_display_title"
        case category
        case defaultModel = "default_model"
        case humanCategoryName = "human_category_name"
        case humanCategoryShortName = "human_category_short_name"
        case shortExplainer = "short_explainer"
        case supportedModels = "supported_models"
        case tagline
    }

    enum ConversationField: String {
        case action
        case model
        case messages
        case parentMessageId = "parent_message_id"
        case conversationId = "conversation_id"
        case historyAndTrainingDisabled = "history_and_training_disabled"
        case conversationMode = "conversation_mode"
        case kind
        case requestedDefaultModel = "requested_default_model"
        case defaultModelSlug = "default_model_slug"
        case title
        case isVisible = "is_visible"
        case currentNodeId = "current_node_id"
        case isArchived = "is_archived"
        case isStarred = "is_starred"
    }

    enum ContextField: String {
        case tools
        case toolChoice = "tool_choice"
        case toolChoices = "tool_choices"
        case gizmoId = "gizmo_id"
        case gizmo
        case gizmoContext = "gizmo_context"
        case projectId = "project_id"
        case project
        case projectContext = "project_context"
        case attachments
    }

    enum MessageField: String {
        case id
        case author
        case role
        case name
        case metadata
        case parentId = "parent_id"
        case modelSlug = "model_slug"
        case finishDetails = "finish_details"
        case type
        case stopTokens = "stop_tokens"
        case createTime = "create_time"
        case updateTime = "update_time"
        case content
        case contentType = "content_type"
        case parts
        case status
        case endTurn = "end_turn"
        case weight
        case recipient
        case channel
    }

    enum HistoryField: String {
        case offset
        case limit
        case isArchived = "is_archived"
        case isStarred = "is_starred"
        case conversationOrigin = "conversation_origin"
        case items
        case total
        case hasMore = "has_more"
        case id
        case title
        case isTemporaryChat = "is_temporary_chat"
        case defaultModelSlug = "default_model_slug"
        case gizmoId = "gizmo_id"
        case conversationTemplateId = "conversation_template_id"
        case conversationId = "conversation_id"
        case createTime = "create_time"
        case updateTime = "update_time"
        case currentNode = "current_node"
        case mapping
        case message
        case parent
        case children
    }

    enum EventField: String {
        case type
        case conversationId = "conversation_id"
        case title
        case message
        case error
        case code
        case detail
        case status
    }

    enum NamespaceClaim: String {
        case sub
    }

    enum Action: String {
        case next
    }

    enum ConversationMode: String {
        case primaryAssistant = "primary_assistant"
    }

    enum ContentType: String {
        case text
    }

    enum FinishType: String {
        case stop
    }

    enum Recipient: String {
        case all
    }

    enum Channel: String {
        case final
    }

    enum ReasoningType: String {
        case none
    }

    enum Origin: String {
        case chatgpt
    }

    enum EventType: String {
        case titleGeneration = "title_generation"
        case messageStreamComplete = "message_stream_complete"
        case conversationDetailMetadata = "conversation_detail_metadata"
    }

    enum StreamStatus: String {
        case streaming = "IS_STREAMING"
        case complete = "COMPLETE"
        case failure = "FAILURE"
    }

    enum ErrorCode: String {
        case serverError = "server_error"
    }
}
