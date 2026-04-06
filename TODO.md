# TODO

- Add missing tools (that're useful anyway)
  - > Tell me about the Thinkstation PGX vs the current gen mac studio
  - [x] websearch
  - [x] webfetch
- Reduce tool/web latency
  - [x] move SSE event parsing to a persistent jq coprocess
  - [x] reduce per-tool jq calls in `process_turn`
  - [x] collapse repeated tool input parsing into shared helpers
  - [x] add benchmark script for tool-turn hot path
  - [x] tighten web tool guidance to discourage redundant searches/fetches
- Bugs found by test suite
  - [x] `is_safe_command` extracts only first word via `awk '{print $1}'`, so multi-word case patterns like `git\ log` never match
  - [x] `ask_permission` in `deny` mode returns 1 before checking `is_safe_command`, blocking read-only commands like `ls`
  - [x] `cleanup_session` returns nonzero when `SESSION_DIR` is empty or nonexistent (`[[ -d ... ]] && rm` short-circuits)
