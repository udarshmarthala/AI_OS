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
            XCTAssertTrue((error as? LocalizedError)?.errorDescription?.contains("action") ?? false)
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
