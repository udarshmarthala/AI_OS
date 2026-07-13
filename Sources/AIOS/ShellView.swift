import SwiftUI
import AIOSCore

struct ShellView: View {
    @ObservedObject var agent: AgentCore
    @ObservedObject var brain: BrainStatus
    var retry: @Sendable () async -> Void

    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            if !brain.online {
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
