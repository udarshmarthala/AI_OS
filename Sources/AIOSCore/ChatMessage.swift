extension JSONValue: @unchecked Sendable {}

public struct ToolCall: Codable, Equatable, Sendable {
    public struct FunctionCall: Codable, Equatable, Sendable {
        public let name: String
        public let arguments: [String: JSONValue]
        public init(name: String, arguments: [String: JSONValue]) {
            self.name = name
            self.arguments = arguments
        }
    }
    public let function: FunctionCall
    public init(function: FunctionCall) { self.function = function }
}

public struct ChatMessage: Codable, Equatable, Sendable {
    public var role: String
    public var content: String
    public var toolCalls: [ToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }

    public init(role: String, content: String, toolCalls: [ToolCall]? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
    }
}
