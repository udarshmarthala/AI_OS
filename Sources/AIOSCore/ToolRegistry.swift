import Foundation

public final class ToolRegistry: @unchecked Sendable {
    private let tools: [String: any Tool]

    public init(tools: [any Tool]) {
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.spec.name, $0) })
    }

    public var specs: [ToolSpec] {
        tools.values.map(\.spec).sorted { $0.name < $1.name }
    }

    public func execute(name: String, args: [String: JSONValue]) async -> String {
        guard let tool = tools[name] else {
            return "Error: unknown tool '\(name)'"
        }
        do {
            return try await tool.execute(args)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return "Error: \(message)"
        }
    }
}
