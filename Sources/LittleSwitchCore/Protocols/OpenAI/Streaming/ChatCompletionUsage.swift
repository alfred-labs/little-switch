import Foundation

struct ChatCompletionUsage: Sendable {
    let promptTokens: Int
    let cachedPromptTokens: Int
    let cacheWritePromptTokens: Int
    let completionTokens: Int
    let reasoningCompletionTokens: Int
    let totalTokens: Int
}
