import Testing
import Foundation
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
        nonisolated(unsafe) var tokens: [String] = []
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
