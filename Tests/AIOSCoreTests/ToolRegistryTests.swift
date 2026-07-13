import Testing
import Foundation
@testable import AIOSCore

struct EchoTool: Tool {
    let spec = ToolSpec(
        name: "echo",
        description: "Echoes back the input",
        parametersJSON: #"{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}"#
    )
    func execute(_ args: [String: JSONValue]) async throws -> String {
        "echo: \(args["text"]?.stringValue ?? "")"
    }
}

struct FailTool: Tool {
    struct Boom: Error, LocalizedError { var errorDescription: String? { "boom" } }
    let spec = ToolSpec(name: "fail", description: "Always fails", parametersJSON: #"{"type":"object","properties":{}}"#)
    func execute(_ args: [String: JSONValue]) async throws -> String { throw Boom() }
}

@Suite struct ToolRegistryTests {
    @Test func dispatchesToNamedTool() async {
        let registry = ToolRegistry(tools: [EchoTool()])
        let result = await registry.execute(name: "echo", args: ["text": .string("hi")])
        #expect(result == "echo: hi")
    }

    @Test func unknownToolReturnsError() async {
        let registry = ToolRegistry(tools: [])
        let result = await registry.execute(name: "nope", args: [:])
        #expect(result.contains("unknown tool"))
    }

    @Test func toolErrorReturnedAsString() async {
        let registry = ToolRegistry(tools: [FailTool()])
        let result = await registry.execute(name: "fail", args: [:])
        #expect(result.contains("boom"))
    }

    @Test func specsSortedByName() {
        let registry = ToolRegistry(tools: [FailTool(), EchoTool()])
        #expect(registry.specs.map(\.name) == ["echo", "fail"])
    }
}
