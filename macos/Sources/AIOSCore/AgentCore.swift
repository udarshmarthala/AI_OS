import Foundation
import Combine

public struct ChatEntry: Identifiable, Equatable, Sendable {
    public enum Role: Sendable { case user, assistant, error, status }
    public let id = UUID()
    public let role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

@MainActor
public final class AgentCore: ObservableObject {
    @Published public private(set) var transcript: [ChatEntry] = []
    @Published public private(set) var isThinking = false

    private let llm: LLMClient
    private let registry: ToolRegistry
    private var history: [ChatMessage]
    private let maxHops = 5

    public init(llm: LLMClient, registry: ToolRegistry) {
        self.llm = llm
        self.registry = registry
        self.history = [ChatMessage(role: "system", content: Self.systemPrompt)]
    }

    public static let systemPrompt = """
    You are AIOS, the AI operating system for this Mac. You control the computer \
    through tools: app_control (launch/quit/list apps) and file_ops \
    (search/open/move/trash files). Use a tool whenever the user asks to act on \
    apps or files. For general questions, answer directly and concisely. \
    Never claim you performed an action unless a tool result confirms it.
    """

    public func send(_ text: String) async {
        transcript.append(ChatEntry(role: .user, text: text))
        history.append(ChatMessage(role: "user", content: text))
        isThinking = true
        defer { isThinking = false }

        for _ in 0..<maxHops {
            let reply: ChatMessage
            do {
                reply = try await llm.chat(messages: history, tools: registry.specs, onToken: { _ in })
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                transcript.append(ChatEntry(role: .error, text: "Brain offline: \(message)"))
                return
            }

            history.append(reply)

            guard let calls = reply.toolCalls, !calls.isEmpty else {
                transcript.append(ChatEntry(role: .assistant, text: reply.content))
                return
            }

            for call in calls {
                transcript.append(ChatEntry(role: .status, text: "▸ \(call.function.name)"))
                let result = await registry.execute(name: call.function.name, args: call.function.arguments)
                history.append(ChatMessage(role: "tool", content: result))
            }
        }
        transcript.append(ChatEntry(role: .assistant, text: "I got stuck in a tool loop and stopped. Try rephrasing."))
    }
}
