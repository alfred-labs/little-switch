import LittleSwitchWire

/// Only client-executed calls pause a native chain for explicit tool input.
/// The shell and remaining hosted-call shapes are opaque in the Wire projection.
enum ResponsesClientToolContinuation {
    private enum UnprojectedKind: String {
        case shellCall = "shell_call"
        case mcpApprovalRequest = "mcp_approval_request"
        case computerCall = "computer_call"
        case applyPatchCall = "apply_patch_call"
        case localShellCall = "local_shell_call"
    }

    private enum ShellCallField: String {
        case environment
    }

    private enum ShellEnvironmentField: String {
        case type
    }

    private enum ShellEnvironmentKind: String {
        case containerReference = "container_reference"
    }

    static func requiresInput(_ item: JSONValue) -> Bool {
        guard let object = item.object,
            let type = object[OpenAIResponsesToolSearchCall.Key.type.rawValue]?.string
        else { return false }
        if type == OpenAIResponsesToolSearchCallType.toolSearchCall.rawValue {
            return object[OpenAIResponsesToolSearchCall.Key.execution.rawValue]?.string
                == OpenAIResponsesToolSearchCallExecution.client.rawValue
        }
        if type == UnprojectedKind.shellCall.rawValue {
            let environment = object[ShellCallField.environment.rawValue]?.object
            return environment?[ShellEnvironmentField.type.rawValue]?.string
                != ShellEnvironmentKind.containerReference.rawValue
        }
        return [
            OpenAIResponsesFunctionCallType.functionCall.rawValue,
            OpenAIResponsesCustomCallType.customToolCall.rawValue,
            UnprojectedKind.mcpApprovalRequest.rawValue,
            UnprojectedKind.computerCall.rawValue,
            UnprojectedKind.applyPatchCall.rawValue,
            UnprojectedKind.localShellCall.rawValue,
        ].contains(type)
    }
}
