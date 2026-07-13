import Testing
import Foundation
@testable import AIOSCore

/// Requires a running Ollama with qwen2.5:14b. Skips otherwise (early return).
@Suite struct LiveIntegrationTests {
    @Test func modelCallsAppControlForLaunchRequest() async throws {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 300
        let client = OllamaClient(model: "qwen2.5:14b", session: URLSession(configuration: config))
        // swift-testing has no skip-by-throw; skip by early return if Ollama not available
        guard await client.healthCheck() else { return }
        let messages = [
            ChatMessage(role: "system", content: AgentCore.systemPrompt),
            ChatMessage(role: "user", content: "Open the Calculator app")
        ]
        let tools = ToolRegistry(tools: [AppTool(), FileTool()]).specs
        let reply = try await client.chat(messages: messages, tools: tools, onToken: { _ in })

        XCTAssertEqual(reply.toolCalls?.first?.function.name, "app_control")
        XCTAssertEqual(reply.toolCalls?.first?.function.arguments["action"], .string("launch"))
    }
}
