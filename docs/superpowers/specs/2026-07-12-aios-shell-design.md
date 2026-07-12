# AIOS — Agent-First macOS Shell (v1 Design)

Date: 2026-07-12
Status: Approved by user

## Vision

Full-screen macOS app that acts as an AI-first "operating system" layer. The user
talks (voice or text) to a local AI, which launches apps, manages files, and
answers questions. Everything local: no cloud, no API keys.

## Scope (v1)

**In:**
- Full-screen SwiftUI shell (hides Dock/menu bar)
- Local LLM via Ollama (Qwen2.5-14B-Instruct, fits 16GB Apple Silicon)
- Voice input via WhisperKit (on-device STT) plus text input
- Core trio of capabilities:
  1. App control — launch, quit, list running apps
  2. File operations — search (Spotlight), open, move, trash
  3. General Q&A — answered directly by the model

**Out (later versions):**
- System settings control (volume, wifi, dark mode)
- In-app automation (AppleScript)
- Screen click/type computer-use
- Cloud model fallback

## Architecture

```
┌─────────────────────────────────────────┐
│  AIOS.app (SwiftUI, full-screen)        │
│  ┌───────────┐  ┌─────────────────────┐ │
│  │ Shell UI  │  │ Agent Core          │ │
│  │ chat feed │←→│ prompt builder      │ │
│  │ voice btn │  │ tool-call parser    │ │
│  │ status bar│  │ conversation memory │ │
│  └───────────┘  └──────┬──────────────┘ │
│  ┌───────────┐         │                │
│  │ WhisperKit│    ┌────▼─────────┐      │
│  │ (STT)     │    │ Tool Registry│      │
│  └───────────┘    │ apps / files │      │
└───────────────────┴────┬─────────┴──────┘
                         │ REST localhost:11434
                   ┌─────▼─────┐
                   │  Ollama   │
                   │Qwen2.5-14B│
                   └───────────┘
```

- Ollama is a prerequisite. App checks on launch; if missing/down, shows a
  banner with install/start instructions and a retry button.
- Agent loop: user message → messages + tool schemas → Ollama `/api/chat`
  (stream) → if tool call, execute and append result, loop (max 5 hops) →
  final text streamed to chat feed.

## Components

| Component | Job | Depends on |
|---|---|---|
| `ShellView` | Full-screen UI: chat feed, input bar, mic button, status bar | AgentCore |
| `AgentCore` | Agent loop, streaming, tool dispatch, conversation memory | OllamaClient, ToolRegistry |
| `OllamaClient` | REST client for `/api/chat` with streaming and tool calls | none |
| `ToolRegistry` | Registers tools, exposes JSON schemas, dispatches execution | AppTool, FileTool |
| `AppTool` | Launch/quit/list apps via NSWorkspace | none |
| `FileTool` | Search via `mdfind`, open, move, trash via FileManager | none |
| `VoiceInput` | Mic capture → WhisperKit transcription → input field | WhisperKit |

Tools conform to a protocol: `Tool { name, description, schema, execute(args) -> String }`.

## Error Handling

- Ollama unreachable → "brain offline" banner, retry, offer to launch `ollama serve`
- Malformed tool-call JSON → one retry with the parse error fed back to the
  model; on second failure, surface a friendly failure message in chat
- File safety: trash instead of delete; confirmation message before moves;
  no privileged operations
- Permission denials (mic) → inline prompt with a deep link to System Settings

## Testing

- Unit: ToolRegistry dispatch, tool argument parsing, OllamaClient against a
  mock local server
- Integration: real Ollama with scripted prompts; assert the expected tool is
  invoked with correct arguments
- Manual: golden path for both voice and text input on a real Mac

## Decisions Log

- Native Swift over Electron/hybrid: product quality, single binary
- Ollama over MLX in-process: easy model swaps, less ML plumbing
- Qwen2.5-14B: best tool-calling ability that fits 16GB RAM
- WhisperKit: proven on-device STT in Swift
- Full computer-use (click/type) deferred: local 14B models unreliable at it
