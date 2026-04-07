# claude.sh

Claude Code rewritten as a bash script. ~1,500 lines. Zero npm packages.

## Why

The original Claude Code is ~380,000 lines of TypeScript with 266 npm dependencies. This does the same core job in bash with just `curl` and `jq`.

## Features

- **Real-time streaming** via FIFO pipe — text appears as Claude generates it
- **6 tools**: Bash, Read, Edit, Write, Glob, Grep
- **Tool chaining** — up to 25 tool calls per turn
- **Permission prompting** — asks before running non-safe commands (`y/n/a`)
- **CLAUDE.md loading** — reads project instructions from CLAUDE.md files up the directory tree
- **Git-aware context** — branch, status, and recent commits in system prompt
- **Session save/resume** — auto-saves on exit, resume with `--resume <id>`
- **Retry with backoff** — exponential retry on 429/529 rate limits
- **Cost tracking** — per-turn and session totals
- **Spinner** — with the original spinner verbs (Clauding, Flibbertigibbeting, etc.)
- **Slash commands** — `/help`, `/cost`, `/model`, `/clear`, `/save`, `/resume`, `/commit`, `/diff`
- **Pipe mode** — `echo "explain this" | ./claude.sh`

## Install

```bash
git clone https://github.com/jdcodes1/claude.sh.git
cd claude.sh
chmod +x claude.sh
```

## Dependencies

- `curl`
- `jq`
- Optional: `rg` (ripgrep) for better search
- Optional: `python3` for the edit tool

Runtime versions are pinned in `.tool-versions`. Install them with [mise](https://mise.jdx.dev/):

```bash
mise install
```

## Usage

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
./claude.sh
```

### Environment Variables

| Variable | Default | Description |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | (required) | Your Anthropic API key |
| `CLAUDE_MODEL` | `claude-sonnet-4-6` | Model to use |
| `CLAUDE_MAX_TOKENS` | `8192` | Max output tokens |
| `ANTHROPIC_API_URL` | `https://api.anthropic.com` | API base URL |
| `CLAUDE_SH_PERMISSIONS` | `ask` | Permission mode: `ask`, `allow`, or `deny` |
| `CLAUDE_SH_BUFFER_OUTPUT` | `false` (optional) | Buffer text and flush at block end instead of streaming |
| `CLAUDE_SH_DEBUG_STREAM` | `false` (optional) | Log SSE delta timestamps to file (e.g. `/tmp/stream.log`) |

### Commands

```txt
/help      — Show help
/cost      — Show session cost
/model     — Show/change model
/clear     — Clear conversation
/save      — Save current session
/resume    — List/resume saved sessions
/commit    — Auto-generate a git commit
/diff      — Show git diff
/quit      — Exit
```

### Resume a Session

```bash
# List saved sessions
./claude.sh
> /resume

# Resume by number
> /resume 1

# Resume from CLI
./claude.sh --resume 20240101-120000-12345
```

## Architecture

```txt
claude.sh          # Main REPL loop, slash commands, process_turn()
lib/
  api.sh           # Anthropic API client, SSE streaming via FIFO, retry
  json.sh          # Message construction, session persistence, CLAUDE.md, git context
  tools.sh         # 6 tool implementations + permission system
  tui.sh           # ANSI colors, spinner, display helpers
```

## How It Works

1. Read user input
2. Build JSON request with `jq` (messages, tools, system prompt)
3. Stream response via `curl` through a FIFO pipe
4. Parse SSE events line-by-line, print text deltas in real-time
5. When tool_use blocks arrive, execute the tools
6. Feed tool results back as messages
7. Loop until Claude stops calling tools

## Comparison

| | claude.sh | Claude Code (TypeScript) |
| --- | --- | --- |
| Lines of code | ~1,500 | ~380,000 |
| Dependencies | curl, jq | 266 npm packages |
| Binary size | 0 (script) | ~200MB node_modules |
| Startup time | Instant | ~500ms |

### Testing

Tests use [bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System):

```bash
bats test/
```

## License

[MIT](LICENSE)
