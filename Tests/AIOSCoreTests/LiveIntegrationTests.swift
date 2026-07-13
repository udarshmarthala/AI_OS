import XCTest
@testable import AIOSCore

/// Requires a running Ollama with qwen2.5:14b. Skips otherwise.
final class LiveIntegrationTests: XCTestCase {
    func testModelCallsAppControlForLaunchRequest() async throws {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 300
        let client = OllamaClient(model: "qwen2.5:14b", session: URLSession(configuration: config))
        guard await client.healthCheck() else {
            throw XCTSkip("Ollama not running or model not pulled")
        }
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
