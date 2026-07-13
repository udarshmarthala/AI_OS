import Testing
import Foundation
@testable import AIOSCore

@Suite struct JSONValueTests {
    @Test func decodesMixedObject() throws {
        let json = #"{"name":"Safari","count":2,"force":true,"tags":["a"],"extra":null}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        guard case .object(let obj) = value else {
            Issue.record("not object")
            return
        }
        #expect(obj["name"] == .string("Safari"))
        #expect(obj["count"] == .number(2))
        #expect(obj["force"] == .bool(true))
        #expect(obj["tags"] == .array([.string("a")]))
        #expect(obj["extra"] == .null)
    }

    @Test func stringValueAccessor() {
        #expect(JSONValue.string("x").stringValue == "x")
        #expect(JSONValue.number(3).stringValue == "3")
        #expect(JSONValue.null.stringValue == nil)
    }

    @Test func roundTrip() throws {
        let original = JSONValue.object(["a": .number(1.5), "b": .array([.bool(false)])])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(original == decoded)
    }
}
