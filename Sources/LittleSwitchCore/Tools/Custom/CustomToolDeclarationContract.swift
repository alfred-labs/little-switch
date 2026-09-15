/// The generated request envelopes deliberately leave tools and tool_choice
/// opaque. These keys own only the nested declaration and selector conversion;
/// root envelope keys continue to come from the generated Wire contracts.
enum CustomToolDeclarationContract {
    enum Key: String {
        case type
        case name
        case namespace
        case tools
        case custom
        case function
        case format
        case description
        case parameters
        case strict
        case allowedTools = "allowed_tools"
    }

    enum Kind: String {
        case namespace
        case custom
        case function
        case allowedTools = "allowed_tools"
    }

    enum FormatKind: String {
        case grammar
    }
}
