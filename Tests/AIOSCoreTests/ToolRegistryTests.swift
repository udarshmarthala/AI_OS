import XCTest
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

final class ToolRegistryTests: XCTestCase {
    func testDispatchesToNamedTool() async {
        let registry = ToolRegistry(tools: [EchoTool()])
        let result = await registry.execute(name: "echo", args: ["text": .string("hi")])
        XCTAssertEqual(result, "echo: hi")
    }

    func testUnknownToolReturnsError() async {
        let registry = ToolRegistry(tools: [])
        let result = await registry.execute(name: "nope", args: [:])
        XCTAssertTrue(result.contains("unknown tool"))
    }

    func testToolErrorReturnedAsString() async {
        let registry = ToolRegistry(tools: [FailTool()])
        let result = await registry.execute(name: "fail", args: [:])
        XCTAssertTrue(result.contains("boom"))
    }

    func testSpecsSortedByName() {
        let registry = ToolRegistry(tools: [FailTool(), EchoTool()])
        XCTAssertEqual(registry.specs.map(\.name), ["echo", "fail"])
    }
}
