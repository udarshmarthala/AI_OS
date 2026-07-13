import SwiftUI
import AIOSCore

@MainActor
final class BrainStatus: ObservableObject {
    @Published var online = true
}

@main
struct AIOSApp: App {
    @StateObject private var agent: AgentCore
    @StateObject private var brain = BrainStatus()
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
            ShellView(agent: agent, brain: brain, retry: checkBrain)
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
        let result = await ollama.healthCheck()
        brain.online = result
    }
}
