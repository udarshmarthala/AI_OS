import Foundation

public struct OllamaClient: LLMClient {
    public struct ClientError: Error, LocalizedError {
        let message: String
        public var errorDescription: String? { message }
    }

    let model: String
    let baseURL: URL
    let session: URLSession

    public init(
        model: String,
        baseURL: URL = URL(string: "http://localhost:11434")!,
        session: URLSession = .shared
    ) {
        self.model = model
        self.baseURL = baseURL
        self.session = session
    }

    private struct StreamChunk: Decodable {
        let message: ChatMessage?
        let done: Bool
    }

    public func chat(
        messages: [ChatMessage],
        tools: [ToolSpec],
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> ChatMessage {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try requestBody(messages: messages, tools: tools)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ClientError(message: "Ollama returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        var content = ""
        var toolCalls: [ToolCall]?
        let decoder = JSONDecoder()

        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let chunk = try decoder.decode(StreamChunk.self, from: Data(trimmed.utf8))
            if let message = chunk.message {
                if !message.content.isEmpty {
                    content += message.content
                    onToken(message.content)
                }
                if let calls = message.toolCalls, !calls.isEmpty {
                    toolCalls = (toolCalls ?? []) + calls
                }
            }
            if chunk.done { break }
        }
        return ChatMessage(role: "assistant", content: content, toolCalls: toolCalls)
    }

    /// Checks Ollama is reachable and the model is pulled.
    public func healthCheck() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 2
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return String(decoding: data, as: UTF8.self).contains(model.split(separator: ":").first ?? "")
    }

    private func requestBody(messages: [ChatMessage], tools: [ToolSpec]) throws -> Data {
        var payload: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messages.map { msg -> [String: Any] in
                var m: [String: Any] = ["role": msg.role, "content": msg.content]
                if let calls = msg.toolCalls {
                    m["tool_calls"] = calls.map { call in
                        ["function": [
                            "name": call.function.name,
                            "arguments": jsonObject(from: call.function.arguments)
                        ]]
                    }
                }
                return m
            }
        ]
        if !tools.isEmpty {
            payload["tools"] = try tools.map { spec -> [String: Any] in
                let params = try JSONSerialization.jsonObject(with: Data(spec.parametersJSON.utf8))
                return ["type": "function", "function": [
                    "name": spec.name,
                    "description": spec.description,
                    "parameters": params
                ]]
            }
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func jsonObject(from args: [String: JSONValue]) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(args),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }
}
