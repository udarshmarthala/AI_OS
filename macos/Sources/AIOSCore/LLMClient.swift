public protocol LLMClient: Sendable {
    /// Sends the conversation; streams content tokens via onToken; returns the full assistant message.
    func chat(
        messages: [ChatMessage],
        tools: [ToolSpec],
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> ChatMessage
}
