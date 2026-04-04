# Local LLM for Agent Feed Summarization

Use a local LLM (running on your Mac via Ollama) to provide real-time AI
summaries of agent activity — like Google Meet or Teams AI meeting notes,
but for your Gas Town agents.

**Cost: $0.** Runs entirely on your machine. No API keys, no cloud calls.

---

## Setup

### 1. Install Ollama

```bash
brew install ollama
brew services start ollama
```

Ollama runs as a background service on `http://localhost:11434`. It provides
an OpenAI-compatible API that any tool can call.

### 2. Pull a model

For M1/M2 with 16GB RAM, Qwen 2.5 3B is the sweet spot (fast, good at summarization):

```bash
ollama pull qwen2.5:3b     # ~2GB download, ~2GB RAM usage
```

Other options:

| Model | Size | RAM | Speed | Quality | Best for |
|-------|------|-----|-------|---------|----------|
| `qwen2.5:1.5b` | 1GB | ~1.5GB | Fastest | OK | Quick summaries |
| `qwen2.5:3b` | 2GB | ~2GB | Fast | Good | **Recommended** |
| `phi3:mini` | 2.3GB | ~2.5GB | Fast | Good | Reasoning tasks |
| `qwen2.5:7b` | 4.7GB | ~5GB | Medium | Better | 32GB+ RAM Macs |
| `llama3.1:8b` | 4.7GB | ~5GB | Medium | Better | 32GB+ RAM Macs |

### 3. Test it

```bash
cd ~/learning-gastown/guides/local-llm
./test-summary.sh                # Uses sample agent events
./test-summary.sh --live         # Uses real events from local VictoriaLogs
./test-summary.sh --live http://localhost:9429/select/logsql/query  # Container VLogs
```

---

## How it works

```
Agent sessions → OTLP → VictoriaLogs → gt feed --agents (TUI)
                                              ↓
                                    Buffer last 30s of events
                                              ↓
                                    Ollama (localhost:11434)
                                              ↓
                                    Summary panel in TUI
```

1. `gt feed --agents` already queries VictoriaLogs for agent tool-call events
2. The planned summary feature buffers recent events (configurable window)
3. Every ~10 seconds, sends the buffer to Ollama's API for summarization
4. Displays the rolling summary in a right-side panel (toggle with `s` key)

The Ollama API is OpenAI-compatible:
```bash
curl http://localhost:11434/api/generate -d '{
  "model": "qwen2.5:3b",
  "prompt": "Summarize: ...",
  "stream": false
}'
```

---

## Integration with gt feed --agents

The TUI will detect Ollama automatically:
1. Check `http://localhost:11434/api/tags` on startup
2. If available, enable the summary panel (hidden by default)
3. Press `s` to toggle the split-screen summary view
4. Summaries update every 10 seconds with the last 30s of events

Environment variables:
- `OLLAMA_URL` — Ollama endpoint (default: `http://localhost:11434`)
- `OLLAMA_MODEL` — Model to use (default: `qwen2.5:3b`)
- `GT_SUMMARY_INTERVAL` — Seconds between summary updates (default: `10`)
- `GT_SUMMARY_WINDOW` — Seconds of events to include (default: `30`)

---

## For containerized setups

Ollama runs on the **host**, not inside the container. The container's TUI
reaches Ollama via the Docker host network:

```yaml
# In docker-compose.override.yml or via gtc
environment:
  OLLAMA_URL: http://host.docker.internal:11434
```

Or run Ollama in its own container:
```yaml
ollama:
  image: ollama/ollama
  ports:
    - "11434:11434"
  volumes:
    - ollama-models:/root/.ollama
  networks:
    - gt-net
```

---

## Apple Intelligence note

macOS has on-device models via Apple Intelligence, but they don't expose a
local HTTP API for third-party apps. Ollama is the practical alternative —
it uses the same Apple Silicon Neural Engine and Metal GPU acceleration
that Apple Intelligence uses, just with open-source models.

If Apple ever exposes a local API (similar to `MLX` or the `Foundation Models`
framework in future macOS), we can add it as an alternative backend.

---

## Troubleshooting

**Ollama not responding:** `brew services restart ollama`

**Model too slow:** Try a smaller model: `ollama pull qwen2.5:1.5b`

**Out of memory:** Check Activity Monitor → Memory. Close other apps or use
a smaller model. 16GB Macs should use 3B or smaller.

**Want better quality:** On 32GB+ Macs: `ollama pull qwen2.5:7b`
