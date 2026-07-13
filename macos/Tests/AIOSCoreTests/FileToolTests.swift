import Testing
import Foundation
@testable import AIOSCore

// Uses a class so deinit can clean up the temp directory.
@Suite final class FileToolTests {
    let tmp: URL

    init() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("aios-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tmp)
    }

    @Test func moveFile() async throws {
        let src = tmp.appendingPathComponent("a.txt")
        let dst = tmp.appendingPathComponent("b.txt")
        try "hello".write(to: src, atomically: true, encoding: .utf8)

        let result = try await FileTool().execute([
            "action": .string("move"),
            "path": .string(src.path),
            "destination": .string(dst.path)
        ])

        #expect(result.contains("Moved"))
        #expect(!FileManager.default.fileExists(atPath: src.path))
        #expect(FileManager.default.fileExists(atPath: dst.path))
    }

    @Test func trashFile() async throws {
        let file = tmp.appendingPathComponent("junk.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)

        let result = try await FileTool().execute([
            "action": .string("trash"),
            "path": .string(file.path)
        ])

        #expect(result.contains("Trashed"))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func missingActionThrows() async {
        await #expect(throws: (any Error).self) {
            _ = try await FileTool().execute([:])
        }
    }

    @Test func moveMissingSourceThrows() async {
        await #expect(throws: (any Error).self) {
            _ = try await FileTool().execute([
                "action": .string("move"),
                "path": .string(tmp.appendingPathComponent("ghost.txt").path),
                "destination": .string(tmp.appendingPathComponent("z.txt").path)
            ])
        }
    }
}
