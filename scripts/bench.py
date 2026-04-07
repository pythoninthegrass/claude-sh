#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "sh>=2.2.2",
# ]
# [tool.uv]
# exclude-newer = "2026-04-30T00:00:00Z"
# ///

# pyright: reportMissingImports=false

"""Benchmark claude.sh hot paths.

Usage:
    bench.py tool-turn [--iterations N]
"""

import argparse
import json
import os
import sys
import textwrap
import time
from pathlib import Path
from sh import bash, ErrorReturnCode


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def run_tool_turn(iterations: int) -> dict[str, object]:
    root = repo_root()
    command = textwrap.dedent(
        r"""
        source ./claude.sh
        blocks='[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"echo hi"}},{"type":"tool_use","id":"toolu_2","name":"Read","input":{"file_path":"/tmp/x"}}]'
        tool_results='[]'
        for ((i=0; i<ITERATIONS; i++)); do
        	tool_lines=$(extract_tool_uses "$blocks")
        	while IFS=$'\t' read -r tool_name tool_id tool_input; do
        		[[ -z "$tool_name" ]] && continue
        		result=$(tool_result_json "$tool_id" 'ok' false)
        		tool_results=$(append_tool_result_json "$tool_results" "$result")
        	done <<< "$tool_lines"
        done
        printf '%s\n' "$tool_results" | jq '{result_count:length}'
        """
    ).strip()

    env = os.environ.copy()
    env["ITERATIONS"] = str(iterations)

    started = time.perf_counter()
    try:
        result = bash("-lc", command, _cwd=root, _env=env, _tty_out=False)
    except ErrorReturnCode as e:
        print(f"Benchmark failed (exit {e.exit_code}): {e.stderr}", file=sys.stderr)
        raise SystemExit(1) from e
    seconds = time.perf_counter() - started
    payload = json.loads(str(result))
    return {
        "benchmark": "tool-turn",
        "iterations": iterations,
        "seconds": seconds,
        "result_count": payload["result_count"],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="benchmark", required=True)

    tool_turn = subparsers.add_parser("tool-turn")
    tool_turn.add_argument("--iterations", type=int, default=1000)

    args = parser.parse_args()

    if args.benchmark == "tool-turn":
        print(json.dumps(run_tool_turn(args.iterations)))


if __name__ == "__main__":
    main()
