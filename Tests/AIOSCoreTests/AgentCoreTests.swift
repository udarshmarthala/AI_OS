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

final class AgentCoreTests: XCTestCase {
    @MainActor
    func testPlainAnswerAppendsToTranscript() async {
        let llm = MockLLM(replies: [ChatMessage(role: "assistant", content: "Paris")])
        let agent = AgentCore(llm: llm, registry: ToolRegistry(tools: []))

        await agent.send("capital of France?")

        XCTAssertEqual(agent.transcript.count, 2)
        XCTAssertEqual(agent.transcript[0].role, .user)
        XCTAssertEqual(agent.transcript[1].role, .assistant)
        XCTAssertEqual(agent.transcript[1].text, "Paris")
    }

    @MainActor
    func testToolCallLoopExecutesAndContinues() async {
        let toolCall = ToolCall(function: .init(name: "echo", arguments: ["text": .string("hi")]))
        let llm = MockLLM(replies: [
            ChatMessage(role: "assistant", content: "", toolCalls: [toolCall]),
            ChatMessage(role: "assistant", content: "Done: echo: hi")
        ])
        let agent = AgentCore(llm: llm, registry: ToolRegistry(tools: [EchoTool()]))

        await agent.send("say hi")

        XCTAssertEqual(agent.transcript.last?.text, "Done: echo: hi")
        // Second LLM call must include the tool result message.
        let secondCall = llm.receivedMessages[1]
        XCTAssertTrue(secondCall.contains { $0.role == "tool" && $0.content == "echo: hi" })
    }

    @MainActor
    func testHopLimitStopsRunawayLoop() async {
        let toolCall = ToolCall(function: .init(name: "echo", arguments: ["text": .string("x")]))
        let looping = ChatMessage(role: "assistant", content: "", toolCalls: [toolCall])
        let llm = MockLLM(replies: Array(repeating: looping, count: 10))
        let agent = AgentCore(llm: llm, registry: ToolRegistry(tools: [EchoTool()]))

        await agent.send("loop forever")

        XCTAssertLessThanOrEqual(llm.receivedMessages.count, 5)
        XCTAssertEqual(agent.transcript.last?.role, .assistant)
    }

    @MainActor
    func testLLMErrorSurfacesInTranscript() async {
        struct FailingLLM: LLMClient {
            struct Down: Error, LocalizedError { var errorDescription: String? { "connection refused" } }
            func chat(messages: [ChatMessage], tools: [ToolSpec],
                      onToken: @escaping @Sendable (String) -> Void) async throws -> ChatMessage {
                throw Down()
            }
        }
        let agent = AgentCore(llm: FailingLLM(), registry: ToolRegistry(tools: []))

        await agent.send("hello")

        XCTAssertTrue(agent.transcript.last?.text.contains("connection refused") ?? false)
        XCTAssertEqual(agent.transcript.last?.role, .error)
    }
}
