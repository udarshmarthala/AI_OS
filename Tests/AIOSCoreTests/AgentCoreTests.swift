import Testing
import Foundation
@testable import AIOSCore

/// Scripted LLM: returns queued replies in order.
final class MockLLM: LLMClient, @unchecked Sendable {
    var replies: [ChatMessage]
    var receivedMessages: [[ChatMessage]] = []
    init(replies: [ChatMessage]) { self.replies = replies }

    func chat(
        messages: [ChatMessage],
        tools: [ToolSpec],
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> ChatMessage {
        receivedMessages.append(messages)
        let reply = replies.removeFirst()
        if !reply.content.isEmpty { onToken(reply.content) }
        return reply
    }
}

@Suite struct AgentCoreTests {
    @Test @MainActor func plainAnswerAppendsToTranscript() async {
        let llm = MockLLM(replies: [ChatMessage(role: "assistant", content: "Paris")])
        let agent = AgentCore(llm: llm, registry: ToolRegistry(tools: []))

        await agent.send("capital of France?")

        #expect(agent.transcript.count == 2)
        #expect(agent.transcript[0].role == .user)
        #expect(agent.transcript[1].role == .assistant)
        #expect(agent.transcript[1].text == "Paris")
    }

    @Test @MainActor func toolCallLoopExecutesAndContinues() async {
        let toolCall = ToolCall(function: .init(name: "echo", arguments: ["text": .string("hi")]))
        let llm = MockLLM(replies: [
            ChatMessage(role: "assistant", content: "", toolCalls: [toolCall]),
            ChatMessage(role: "assistant", content: "Done: echo: hi")
        ])
        let agent = AgentCore(llm: llm, registry: ToolRegistry(tools: [EchoTool()]))

        await agent.send("say hi")

        #expect(agent.transcript.last?.text == "Done: echo: hi")
        // Second LLM call must include the tool result message.
        let secondCall = llm.receivedMessages[1]
        #expect(secondCall.contains { $0.role == "tool" && $0.content == "echo: hi" })
    }

    @Test @MainActor func hopLimitStopsRunawayLoop() async {
        let toolCall = ToolCall(function: .init(name: "echo", arguments: ["text": .string("x")]))
        let looping = ChatMessage(role: "assistant", content: "", toolCalls: [toolCall])
        let llm = MockLLM(replies: Array(repeating: looping, count: 10))
        let agent = AgentCore(llm: llm, registry: ToolRegistry(tools: [EchoTool()]))

        await agent.send("loop forever")

        #expect(llm.receivedMessages.count <= 5)
        #expect(agent.transcript.last?.role == .assistant)
    }

    @Test @MainActor func llmErrorSurfacesInTranscript() async {
        struct FailingLLM: LLMClient {
            struct Down: Error, LocalizedError { var errorDescription: String? { "connection refused" } }
            func chat(messages: [ChatMessage], tools: [ToolSpec],
                      onToken: @escaping @Sendable (String) -> Void) async throws -> ChatMessage {
                throw Down()
            }
        }
        let agent = AgentCore(llm: FailingLLM(), registry: ToolRegistry(tools: []))

        await agent.send("hello")

        #expect(agent.transcript.last?.text.contains("connection refused") == true)
        #expect(agent.transcript.last?.role == .error)
    }
}
