# AIOS — an AI-first shell for macOS

Talk to your Mac. A local LLM launches apps, manages files, and answers
questions. Fully offline: Ollama for the brain, WhisperKit for voice.

## Requirements
- macOS 14+, Apple Silicon, 16GB RAM
- [Ollama](https://ollama.com) with `qwen2.5:14b`

## Setup
```bash
brew install ollama
brew services start ollama
ollama pull qwen2.5:14b
swift run AIOS
```

## What it can do (v1)
- "Open Safari" / "Quit Music" / "What apps are running?"
- "Find files named invoice" / "Move ~/Downloads/x.pdf to ~/Documents"
- Any general question — answered locally
- Voice: click the mic, speak, click again

## Tests
```bash
swift test                                  # unit tests (offline)
swift test --filter LiveIntegrationTests    # needs Ollama running
```

## Design
See `docs/superpowers/specs/2026-07-12-aios-shell-design.md`.
