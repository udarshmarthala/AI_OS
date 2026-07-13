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
