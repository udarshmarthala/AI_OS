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

// .serialized because MockURLProtocol uses shared mutable statics
@Suite(.serialized) struct OllamaClientTests {
    func makeClient() -> OllamaClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return OllamaClient(model: "qwen2.5:14b", session: URLSession(configuration: config))
    }

    @Test func streamsContentTokens() async throws {
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
        #expect(reply.content == "Hello")
        #expect(tokens == ["Hel", "lo"])
        #expect(reply.toolCalls == nil)
    }

    @Test func parsesToolCalls() async throws {
        MockURLProtocol.responseBody = """
        {"message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"app_control","arguments":{"action":"launch","name":"Safari"}}}]},"done":true}
        """
        let reply = try await makeClient().chat(
            messages: [ChatMessage(role: "user", content: "open safari")],
            tools: [],
            onToken: { _ in }
        )
        #expect(reply.toolCalls?.count == 1)
        #expect(reply.toolCalls?.first?.function.name == "app_control")
        #expect(reply.toolCalls?.first?.function.arguments["name"] == .string("Safari"))
    }

    @Test func sendsToolSchemasInRequest() async throws {
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
        #expect(body.contains(#""name":"echo""#))
        #expect(body.contains(#""type":"function""#))
    }
}
