# AIOS v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full-screen macOS "AI shell" app: user talks (voice/text) to a local LLM that launches apps, manages files, and answers questions.

**Architecture:** SwiftUI executable (`AIOS`) on top of a UI-free library (`AIOSCore`) containing the agent loop, Ollama REST client, and tools. AgentCore talks to an `LLMClient` protocol so all agent logic is testable with mocks. Ollama (qwen2.5:14b) serves the model on localhost:11434; WhisperKit does on-device STT.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Package Manager, XCTest, Ollama REST API, WhisperKit, AVFoundation.

**Prerequisites (run once, before Task 1):**
```bash
# Install Ollama and the model (~9GB download)
brew install ollama
brew services start ollama   # or run `ollama serve` in a terminal
ollama pull qwen2.5:14b
# Verify:
curl -s http://localhost:11434/api/tags | grep qwen2.5
```

**File map (final state):**

```
Package.swift
Sources/AIOSCore/JSONValue.swift        — arbitrary-JSON Codable enum
Sources/AIOSCore/Tool.swift             — Tool protocol + ToolSpec
Sources/AIOSCore/ToolRegistry.swift     — name→tool dispatch
Sources/AIOSCore/AppTool.swift          — launch/quit/list apps
Sources/AIOSCore/FileTool.swift         — search/open/move/trash files
Sources/AIOSCore/ChatMessage.swift      — chat + tool-call models
Sources/AIOSCore/LLMClient.swift        — protocol
Sources/AIOSCore/OllamaClient.swift     — streaming REST client
Sources/AIOSCore/AgentCore.swift        — agent loop + transcript
Sources/AIOS/AIOSApp.swift              — @main, full-screen window
Sources/AIOS/ShellView.swift            — chat UI
Sources/AIOS/VoiceInput.swift           — mic capture + WhisperKit
Tests/AIOSCoreTests/JSONValueTests.swift
Tests/AIOSCoreTests/ToolRegistryTests.swift
Tests/AIOSCoreTests/FileToolTests.swift
Tests/AIOSCoreTests/OllamaClientTests.swift
Tests/AIOSCoreTests/AgentCoreTests.swift
```

---

### Task 1: Package scaffold

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/AIOSCore/JSONValue.swift` (placeholder-free stub comes in Task 2)
- Create: `Sources/AIOS/main.swift` (temporary, replaced in Task 8)

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIOS",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
    ],
    targets: [
        .target(name: "AIOSCore"),
        .executableTarget(
            name: "AIOS",
            dependencies: [
                "AIOSCore",
                .product(name: "WhisperKit", package: "WhisperKit")
            ]
        ),
        .testTarget(name: "AIOSCoreTests", dependencies: ["AIOSCore"])
    ]
)
```

- [ ] **Step 2: Write .gitignore**

```
.build/
.swiftpm/
*.xcodeproj
DerivedData/
```

- [ ] **Step 3: Create minimal source files so the package builds**

`Sources/AIOSCore/JSONValue.swift`:
```swift
// Filled in Task 2.
public enum JSONValue {}
```

`Sources/AIOS/main.swift`:
```swift
print("AIOS placeholder — replaced in Task 8")
```

Create empty test dir file `Tests/AIOSCoreTests/JSONValueTests.swift`:
```swift
import XCTest
final class PackageSmokeTests: XCTestCase {
    func testPackageBuilds() { XCTAssertTrue(true) }
}
```

- [ ] **Step 4: Verify build + tests**

Run: `swift build && swift test`
Expected: Build succeeds (first run resolves WhisperKit, takes a few minutes); 1 test passes.

- [ ] **Step 5: Commit**

```bash
git add Package.swift .gitignore Sources Tests
git commit -m "chore: scaffold SPM package with AIOSCore, AIOS, tests"
```

---

### Task 2: JSONValue

**Files:**
- Modify: `Sources/AIOSCore/JSONValue.swift`
- Modify: `Tests/AIOSCoreTests/JSONValueTests.swift`

- [ ] **Step 1: Write failing tests**

Replace `Tests/AIOSCoreTests/JSONValueTests.swift` with:
```swift
import XCTest
@testable import AIOSCore

final class JSONValueTests: XCTestCase {
    func testDecodesMixedObject() throws {
        let json = #"{"name":"Safari","count":2,"force":true,"tags":["a"],"extra":null}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        guard case .object(let obj) = value else { return XCTFail("not object") }
        XCTAssertEqual(obj["name"], .string("Safari"))
        XCTAssertEqual(obj["count"], .number(2))
        XCTAssertEqual(obj["force"], .bool(true))
        XCTAssertEqual(obj["tags"], .array([.string("a")]))
        XCTAssertEqual(obj["extra"], .null)
    }

    func testStringValueAccessor() {
        XCTAssertEqual(JSONValue.string("x").stringValue, "x")
        XCTAssertEqual(JSONValue.number(3).stringValue, "3")
        XCTAssertNil(JSONValue.null.stringValue)
    }

    func testRoundTrip() throws {
        let original = JSONValue.object(["a": .number(1.5), "b": .array([.bool(false)])])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
```

- [ ] **Step 2: Run tests, verify failure**

Run: `swift test --filter JSONValueTests`
Expected: FAIL (JSONValue has no cases/conformances yet).

- [ ] **Step 3: Implement JSONValue**

Replace `Sources/AIOSCore/JSONValue.swift` with:
```swift
public enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }

    /// String form for tool arguments. Numbers render without trailing ".0" when integral.
    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n):
            return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .bool(let b): return String(b)
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test --filter JSONValueTests`
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AIOSCore/JSONValue.swift Tests/AIOSCoreTests/JSONValueTests.swift
git commit -m "feat: add JSONValue for arbitrary tool-call arguments"
```

---

### Task 3: Tool protocol + ToolRegistry

**Files:**
- Create: `Sources/AIOSCore/Tool.swift`
- Create: `Sources/AIOSCore/ToolRegistry.swift`
- Create: `Tests/AIOSCoreTests/ToolRegistryTests.swift`

- [ ] **Step 1: Write failing tests**

`Tests/AIOSCoreTests/ToolRegistryTests.swift`:
```swift
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
```

- [ ] **Step 2: Run tests, verify failure**

Run: `swift test --filter ToolRegistryTests`
Expected: FAIL — `Tool`, `ToolSpec`, `ToolRegistry` undefined.

- [ ] **Step 3: Implement Tool + ToolRegistry**

`Sources/AIOSCore/Tool.swift`:
```swift
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
```

`Sources/AIOSCore/ToolRegistry.swift`:
```swift
public final class ToolRegistry: @unchecked Sendable {
    private let tools: [String: Tool]

    public init(tools: [Tool]) {
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
            return "Error: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test --filter ToolRegistryTests`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AIOSCore/Tool.swift Sources/AIOSCore/ToolRegistry.swift Tests/AIOSCoreTests/ToolRegistryTests.swift
git commit -m "feat: add Tool protocol and ToolRegistry dispatch"
```

---

### Task 4: FileTool

**Files:**
- Create: `Sources/AIOSCore/FileTool.swift`
- Create: `Tests/AIOSCoreTests/FileToolTests.swift`

Actions: `search` (mdfind), `open` (NSWorkspace), `move`, `trash`. Trash instead of delete — spec safety rule.

- [ ] **Step 1: Write failing tests**

`Tests/AIOSCoreTests/FileToolTests.swift`:
```swift
import XCTest
@testable import AIOSCore

final class FileToolTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("aios-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testMoveFile() async throws {
        let src = tmp.appendingPathComponent("a.txt")
        let dst = tmp.appendingPathComponent("b.txt")
        try "hello".write(to: src, atomically: true, encoding: .utf8)

        let result = try await FileTool().execute([
            "action": .string("move"),
            "path": .string(src.path),
            "destination": .string(dst.path)
        ])

        XCTAssertTrue(result.contains("Moved"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.path))
    }

    func testTrashFile() async throws {
        let file = tmp.appendingPathComponent("junk.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)

        let result = try await FileTool().execute([
            "action": .string("trash"),
            "path": .string(file.path)
        ])

        XCTAssertTrue(result.contains("Trashed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testMissingActionThrows() async {
        do {
            _ = try await FileTool().execute([:])
            XCTFail("should throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("action"))
        }
    }

    func testMoveMissingSourceThrows() async {
        do {
            _ = try await FileTool().execute([
                "action": .string("move"),
                "path": .string(tmp.appendingPathComponent("ghost.txt").path),
                "destination": .string(tmp.appendingPathComponent("z.txt").path)
            ])
            XCTFail("should throw")
        } catch {
            // any thrown error is fine — FileManager reports missing file
        }
    }
}
```

- [ ] **Step 2: Run tests, verify failure**

Run: `swift test --filter FileToolTests`
Expected: FAIL — `FileTool` undefined.

- [ ] **Step 3: Implement FileTool**

`Sources/AIOSCore/FileTool.swift`:
```swift
import Foundation
import AppKit

public struct FileTool: Tool {
    public struct ToolError: Error, LocalizedError {
        let message: String
        public var errorDescription: String? { message }
    }

    public let spec = ToolSpec(
        name: "file_ops",
        description: "File operations: search files by name, open a file, move a file, or put a file in the Trash. Never permanently deletes.",
        parametersJSON: """
        {"type":"object","properties":{
          "action":{"type":"string","enum":["search","open","move","trash"],"description":"Operation to perform"},
          "query":{"type":"string","description":"Filename query for search"},
          "path":{"type":"string","description":"Absolute file path for open/move/trash"},
          "destination":{"type":"string","description":"Absolute destination path for move"}
        },"required":["action"]}
        """
    )

    public init() {}

    public func execute(_ args: [String: JSONValue]) async throws -> String {
        guard let action = args["action"]?.stringValue else {
            throw ToolError(message: "missing 'action' argument")
        }
        switch action {
        case "search":
            guard let query = args["query"]?.stringValue else {
                throw ToolError(message: "search requires 'query'")
            }
            return try search(query: query)
        case "open":
            let path = try requirePath(args)
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return "Opened \(path)"
        case "move":
            let path = try requirePath(args)
            guard let dest = args["destination"]?.stringValue else {
                throw ToolError(message: "move requires 'destination'")
            }
            try FileManager.default.moveItem(atPath: path, toPath: dest)
            return "Moved \(path) -> \(dest)"
        case "trash":
            let path = try requirePath(args)
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            return "Trashed \(path)"
        default:
            throw ToolError(message: "unknown action '\(action)'")
        }
    }

    private func requirePath(_ args: [String: JSONValue]) throws -> String {
        guard let path = args["path"]?.stringValue else {
            throw ToolError(message: "missing 'path' argument")
        }
        return path
    }

    private func search(query: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-name", query]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n").prefix(20)
        return lines.isEmpty ? "No files found for '\(query)'" : lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test --filter FileToolTests`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AIOSCore/FileTool.swift Tests/AIOSCoreTests/FileToolTests.swift
git commit -m "feat: add FileTool (search/open/move/trash)"
```

---

### Task 5: AppTool

**Files:**
- Create: `Sources/AIOSCore/AppTool.swift`
- Test: manual (NSWorkspace side effects; arg validation covered by same pattern as FileTool)

- [ ] **Step 1: Implement AppTool**

`Sources/AIOSCore/AppTool.swift`:
```swift
import Foundation
import AppKit

public struct AppTool: Tool {
    public struct ToolError: Error, LocalizedError {
        let message: String
        public var errorDescription: String? { message }
    }

    public let spec = ToolSpec(
        name: "app_control",
        description: "Control macOS applications: launch an app by name, quit an app by name, or list running apps.",
        parametersJSON: """
        {"type":"object","properties":{
          "action":{"type":"string","enum":["launch","quit","list"],"description":"Operation to perform"},
          "name":{"type":"string","description":"Application name, e.g. 'Safari' (required for launch/quit)"}
        },"required":["action"]}
        """
    )

    public init() {}

    public func execute(_ args: [String: JSONValue]) async throws -> String {
        guard let action = args["action"]?.stringValue else {
            throw ToolError(message: "missing 'action' argument")
        }
        switch action {
        case "launch":
            let name = try requireName(args)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", name]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ToolError(message: "could not find app '\(name)'")
            }
            return "Launched \(name)"
        case "quit":
            let name = try requireName(args)
            let running = NSWorkspace.shared.runningApplications
                .filter { $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame }
            guard !running.isEmpty else {
                throw ToolError(message: "'\(name)' is not running")
            }
            running.forEach { $0.terminate() }
            return "Quit \(name)"
        case "list":
            let names = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap(\.localizedName)
                .sorted()
            return names.isEmpty ? "No apps running" : names.joined(separator: ", ")
        default:
            throw ToolError(message: "unknown action '\(action)'")
        }
    }

    private func requireName(_ args: [String: JSONValue]) throws -> String {
        guard let name = args["name"]?.stringValue else {
            throw ToolError(message: "missing 'name' argument")
        }
        return name
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Manual smoke test**

Run in `swift repl` is awkward; instead temporarily verify via a tiny script — or wait for Task 9 integration test which covers launch. Quick check with existing tests still green:
`swift test`
Expected: all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/AIOSCore/AppTool.swift
git commit -m "feat: add AppTool (launch/quit/list apps)"
```

---

### Task 6: ChatMessage models + OllamaClient

**Files:**
- Create: `Sources/AIOSCore/ChatMessage.swift`
- Create: `Sources/AIOSCore/LLMClient.swift`
- Create: `Sources/AIOSCore/OllamaClient.swift`
- Create: `Tests/AIOSCoreTests/OllamaClientTests.swift`

Ollama `/api/chat` streams NDJSON: `{"message":{"role":"assistant","content":"tok","tool_calls":[...]},"done":false}` per line. Tool calls arrive whole in one chunk.

- [ ] **Step 1: Write models**

`Sources/AIOSCore/ChatMessage.swift`:
```swift
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
    public var role: String       // "system" | "user" | "assistant" | "tool"
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
}
```

`Sources/AIOSCore/LLMClient.swift`:
```swift
public protocol LLMClient: Sendable {
    /// Sends the conversation; streams content tokens via onToken; returns the full assistant message.
    func chat(
        messages: [ChatMessage],
        tools: [ToolSpec],
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> ChatMessage
}
```

- [ ] **Step 2: Write failing tests (mock URLProtocol)**

`Tests/AIOSCoreTests/OllamaClientTests.swift`:
```swift
import XCTest
@testable import AIOSCore

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseBody = ""
    nonisolated(unsafe) static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let bufSize = 4096
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            defer { buf.deallocate(); stream.close() }
            while stream.hasBytesAvailable {
                let read = stream.read(buf, maxLength: bufSize)
                if read <= 0 { break }
                data.append(buf, count: read)
            }
            Self.lastRequestBody = data
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/x-ndjson"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class OllamaClientTests: XCTestCase {
    func makeClient() -> OllamaClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return OllamaClient(model: "qwen2.5:14b", session: URLSession(configuration: config))
    }

    func testStreamsContentTokens() async throws {
        MockURLProtocol.responseBody = """
        {"message":{"role":"assistant","content":"Hel"},"done":false}
        {"message":{"role":"assistant","content":"lo"},"done":false}
        {"message":{"role":"assistant","content":""},"done":true}
        """
        var tokens: [String] = []
        let reply = try await makeClient().chat(
            messages: [ChatMessage(role: "user", content: "hi")],
            tools: [],
            onToken: { tokens.append($0) }
        )
        XCTAssertEqual(reply.content, "Hello")
        XCTAssertEqual(tokens, ["Hel", "lo"])
        XCTAssertNil(reply.toolCalls)
    }

    func testParsesToolCalls() async throws {
        MockURLProtocol.responseBody = """
        {"message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"app_control","arguments":{"action":"launch","name":"Safari"}}}]},"done":true}
        """
        let reply = try await makeClient().chat(
            messages: [ChatMessage(role: "user", content: "open safari")],
            tools: [],
            onToken: { _ in }
        )
        XCTAssertEqual(reply.toolCalls?.count, 1)
        XCTAssertEqual(reply.toolCalls?.first?.function.name, "app_control")
        XCTAssertEqual(reply.toolCalls?.first?.function.arguments["name"], .string("Safari"))
    }

    func testSendsToolSchemasInRequest() async throws {
        MockURLProtocol.responseBody = #"{"message":{"role":"assistant","content":"ok"},"done":true}"#
        let spec = ToolSpec(
            name: "echo", description: "d",
            parametersJSON: #"{"type":"object","properties":{}}"#
        )
        _ = try await makeClient().chat(
            messages: [ChatMessage(role: "user", content: "x")],
            tools: [spec],
            onToken: { _ in }
        )
        let body = String(decoding: MockURLProtocol.lastRequestBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains(#""name":"echo""#))
        XCTAssertTrue(body.contains(#""type":"function""#))
    }
}
```

- [ ] **Step 3: Run tests, verify failure**

Run: `swift test --filter OllamaClientTests`
Expected: FAIL — `OllamaClient` undefined.

- [ ] **Step 4: Implement OllamaClient**

`Sources/AIOSCore/OllamaClient.swift`:
```swift
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
            guard !line.isEmpty else { continue }
            let chunk = try decoder.decode(StreamChunk.self, from: Data(line.utf8))
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
```

- [ ] **Step 5: Run tests, verify pass**

Run: `swift test --filter OllamaClientTests`
Expected: 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AIOSCore/ChatMessage.swift Sources/AIOSCore/LLMClient.swift Sources/AIOSCore/OllamaClient.swift Tests/AIOSCoreTests/OllamaClientTests.swift
git commit -m "feat: add ChatMessage models and streaming OllamaClient"
```

---

### Task 7: AgentCore

**Files:**
- Create: `Sources/AIOSCore/AgentCore.swift`
- Create: `Tests/AIOSCoreTests/AgentCoreTests.swift`

Agent loop: send messages+tools → if reply has tool calls, execute each, append `tool` messages, loop (max 5 hops) → publish final text.

- [ ] **Step 1: Write failing tests**

`Tests/AIOSCoreTests/AgentCoreTests.swift`:
```swift
import XCTest
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
```

- [ ] **Step 2: Run tests, verify failure**

Run: `swift test --filter AgentCoreTests`
Expected: FAIL — `AgentCore`, `ChatEntry` undefined.

- [ ] **Step 3: Implement AgentCore**

`Sources/AIOSCore/AgentCore.swift`:
```swift
import Foundation

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

    static let systemPrompt = """
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
                transcript.append(ChatEntry(role: .error, text: "Brain offline: \(error.localizedDescription)"))
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
```

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test --filter AgentCoreTests`
Expected: 4 tests PASS. Note: `testHopLimitStopsRunawayLoop` counts LLM calls ≤ 5.

- [ ] **Step 5: Run whole suite**

Run: `swift test`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AIOSCore/AgentCore.swift Tests/AIOSCoreTests/AgentCoreTests.swift
git commit -m "feat: add AgentCore agent loop with tool dispatch and hop limit"
```

---

### Task 8: Shell UI + full-screen app

**Files:**
- Delete: `Sources/AIOS/main.swift`
- Create: `Sources/AIOS/AIOSApp.swift`
- Create: `Sources/AIOS/ShellView.swift`

- [ ] **Step 1: Implement app entry**

Delete `Sources/AIOS/main.swift`. Create `Sources/AIOS/AIOSApp.swift`:
```swift
import SwiftUI
import AIOSCore

@main
struct AIOSApp: App {
    @StateObject private var agent: AgentCore
    @State private var brainOnline = true
    private let ollama = OllamaClient(model: "qwen2.5:14b")

    init() {
        let registry = ToolRegistry(tools: [AppTool(), FileTool()])
        _agent = StateObject(wrappedValue: AgentCore(
            llm: OllamaClient(model: "qwen2.5:14b"),
            registry: registry
        ))
    }

    var body: some Scene {
        WindowGroup {
            ShellView(agent: agent, brainOnline: $brainOnline, retry: checkBrain)
                .task { await checkBrain() }
                .onAppear {
                    NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
                    if let window = NSApp.windows.first {
                        window.toggleFullScreen(nil)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
    }

    @Sendable func checkBrain() async {
        brainOnline = await ollama.healthCheck()
    }
}
```

- [ ] **Step 2: Implement ShellView**

`Sources/AIOS/ShellView.swift`:
```swift
import SwiftUI
import AIOSCore

struct ShellView: View {
    @ObservedObject var agent: AgentCore
    @Binding var brainOnline: Bool
    var retry: @Sendable () async -> Void

    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            if !brainOnline {
                offlineBanner
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(agent.transcript) { entry in
                            entryView(entry).id(entry.id)
                        }
                    }
                    .padding(24)
                }
                .onChange(of: agent.transcript.count) {
                    if let last = agent.transcript.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            inputBar
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    private var offlineBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Brain offline — start Ollama: `brew services start ollama`, then `ollama pull qwen2.5:14b`")
            Button("Retry") { Task { await retry() } }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.85))
        .foregroundColor(.black)
    }

    @ViewBuilder
    private func entryView(_ entry: ChatEntry) -> some View {
        switch entry.role {
        case .user:
            Text(entry.text)
                .padding(12)
                .background(Color.blue.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant:
            Text(entry.text)
                .padding(12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .status:
            Text(entry.text)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
        case .error:
            Text(entry.text)
                .padding(12)
                .foregroundColor(.orange)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask AIOS anything…", text: $input)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(14)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .onSubmit(submit)
                .disabled(agent.isThinking)
            if agent.isThinking {
                ProgressView().controlSize(.small)
            }
        }
        .padding(20)
    }

    private func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        Task { await agent.send(text) }
    }
}
```

- [ ] **Step 3: Build and run manually**

Run: `swift build && swift run AIOS`
Expected: full-screen dark window, input bar. With Ollama running, type "what is 2+2" → answer appears. Type "open Safari" → status line `▸ app_control`, Safari launches, confirmation text. Type "find files named resume" → `▸ file_ops`, results listed.
If Ollama stopped (`brew services stop ollama`): orange banner appears; Retry works after restart.

- [ ] **Step 4: Commit**

```bash
git add Sources/AIOS
git rm Sources/AIOS/main.swift 2>/dev/null || true
git commit -m "feat: add full-screen SwiftUI shell with chat UI and offline banner"
```

---

### Task 9: Voice input (WhisperKit)

**Files:**
- Create: `Sources/AIOS/VoiceInput.swift`
- Modify: `Sources/AIOS/ShellView.swift` (add mic button)

- [ ] **Step 1: Implement VoiceInput**

`Sources/AIOS/VoiceInput.swift`:
```swift
import Foundation
import AVFoundation
import WhisperKit

@MainActor
final class VoiceInput: ObservableObject {
    enum State: Equatable { case idle, loading, recording, transcribing, denied }
    @Published var state: State = .idle

    private var whisper: WhisperKit?
    private let engine = AVAudioEngine()
    private var samples: [Float] = []

    func toggle(onText: @escaping (String) -> Void) {
        switch state {
        case .recording:
            stopAndTranscribe(onText: onText)
        case .idle:
            Task { await start() }
        default:
            break
        }
    }

    private func start() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else {
            state = .denied
            return
        }
        if whisper == nil {
            state = .loading
            whisper = try? await WhisperKit(model: "base.en")
            guard whisper != nil else { state = .idle; return }
        }
        samples = []
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)!

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            let ratio = 16000.0 / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var error: NSError?
            var consumed = false
            converter.convert(to: converted, error: &error) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let channel = converted.floatChannelData else { return }
            let chunk = Array(UnsafeBufferPointer(start: channel[0], count: Int(converted.frameLength)))
            Task { @MainActor [weak self] in self?.samples.append(contentsOf: chunk) }
        }

        do {
            try engine.start()
            state = .recording
        } catch {
            state = .idle
        }
    }

    private func stopAndTranscribe(onText: @escaping (String) -> Void) {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        state = .transcribing
        let audio = samples
        Task {
            let results = try? await whisper?.transcribe(audioArray: audio)
            let text = results?.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            state = .idle
            if !text.isEmpty { onText(text) }
        }
    }
}
```

- [ ] **Step 2: Add mic button to ShellView**

In `Sources/AIOS/ShellView.swift`, add property after `@State private var input = ""`:
```swift
    @StateObject private var voice = VoiceInput()
```

Replace the `inputBar` computed property with:
```swift
    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask AIOS anything…", text: $input)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(14)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .onSubmit(submit)
                .disabled(agent.isThinking)
            micButton
            if agent.isThinking {
                ProgressView().controlSize(.small)
            }
        }
        .padding(20)
    }

    private var micButton: some View {
        Button {
            voice.toggle { text in
                input = text
                submit()
            }
        } label: {
            Image(systemName: voice.state == .recording ? "mic.fill" : "mic")
                .font(.title2)
                .foregroundColor(voice.state == .recording ? .red : .primary)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if voice.state == .loading { Text("loading model…").font(.caption2).fixedSize().offset(y: 16) }
            if voice.state == .transcribing { Text("transcribing…").font(.caption2).fixedSize().offset(y: 16) }
            if voice.state == .denied {
                Link("mic denied — open Settings",
                     destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    .font(.caption2).fixedSize().offset(y: 16)
            }
        }
    }
```

Add `import AVFoundation` is NOT needed in ShellView (VoiceInput encapsulates it).

- [ ] **Step 3: Build and manual test**

Run: `swift build && swift run AIOS`
Expected: mic button visible. Click → macOS mic permission prompt (attributed to terminal in dev) → "loading model…" first time (WhisperKit downloads base.en, ~150MB) → red mic while recording. Say "open calculator", click again → transcribed, sent, Calculator launches.

- [ ] **Step 4: Commit**

```bash
git add Sources/AIOS/VoiceInput.swift Sources/AIOS/ShellView.swift
git commit -m "feat: add voice input via WhisperKit with mic button"
```

---

### Task 10: Live integration test + README

**Files:**
- Create: `Tests/AIOSCoreTests/LiveIntegrationTests.swift`
- Create: `README.md`

- [ ] **Step 1: Write live integration test (skips when Ollama down)**

`Tests/AIOSCoreTests/LiveIntegrationTests.swift`:
```swift
import XCTest
@testable import AIOSCore

/// Requires a running Ollama with qwen2.5:14b. Skips otherwise.
final class LiveIntegrationTests: XCTestCase {
    func testModelCallsAppControlForLaunchRequest() async throws {
        let client = OllamaClient(model: "qwen2.5:14b")
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
```

- [ ] **Step 2: Run it live**

Run: `swift test --filter LiveIntegrationTests`
Expected: PASS with Ollama up (takes ~10-30s, model inference). SKIP when down.

- [ ] **Step 3: Write README**

`README.md`:
```markdown
# AIOS — an AI-first shell for macOS

Talk to your Mac. A local LLM launches apps, manages files, and answers
questions. Fully offline: Ollama for the brain, WhisperKit for voice.

## Requirements
- macOS 14+, Apple Silicon, 16GB RAM
- [Ollama](https://ollama.com) with `qwen2.5:14b`

## Setup
```bash
brew install ollama
brew services start ollama
ollama pull qwen2.5:14b
swift run AIOS
```

## What it can do (v1)
- "Open Safari" / "Quit Music" / "What apps are running?"
- "Find files named invoice" / "Move ~/Downloads/x.pdf to ~/Documents"
- Any general question — answered locally
- Voice: click the mic, speak, click again

## Tests
```bash
swift test                                  # unit tests (offline)
swift test --filter LiveIntegrationTests    # needs Ollama running
```

## Design
See `docs/superpowers/specs/2026-07-12-aios-shell-design.md`.
```

- [ ] **Step 4: Full suite + commit**

Run: `swift test`
Expected: all PASS (live test passes or skips).

```bash
git add Tests/AIOSCoreTests/LiveIntegrationTests.swift README.md
git commit -m "test: add live Ollama integration test; add README"
```

---

## Manual Acceptance Checklist (after Task 10)

- [ ] `swift run AIOS` → full-screen dark shell
- [ ] "what is the capital of Japan" → direct answer, no tool call
- [ ] "open Safari" → Safari launches, confirmation in chat
- [ ] "quit Safari" → Safari quits
- [ ] "what apps are running" → list appears
- [ ] "find files named resume" → paths listed
- [ ] Voice: mic → "open calculator" → mic → Calculator launches
- [ ] Stop Ollama → banner appears; start Ollama → Retry clears it
