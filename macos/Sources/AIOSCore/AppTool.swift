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
            let running = await MainActor.run {
                NSWorkspace.shared.runningApplications
                    .filter { $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame }
            }
            guard !running.isEmpty else {
                throw ToolError(message: "'\(name)' is not running")
            }
            running.forEach { $0.terminate() }
            return "Quit \(name)"
        case "list":
            let names = await MainActor.run {
                NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .regular }
                    .compactMap(\.localizedName)
                    .sorted()
            }
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
