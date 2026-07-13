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
