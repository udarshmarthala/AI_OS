public struct ToolSpec: Equatable, Sendable {
    public let name: String
    public let description: String
    /// JSON-schema string for the tool's parameters.
    public let parametersJSON: String

    public init(name: String, description: String, parametersJSON: String) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }
}

public protocol Tool: Sendable {
    var spec: ToolSpec { get }
    func execute(_ args: [String: JSONValue]) async throws -> String
}
