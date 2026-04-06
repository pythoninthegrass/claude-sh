#!/usr/bin/env bats

load test_helper

setup() {
	setup_stubs
	setup_tempdir
}

teardown() {
	teardown_tempdir
}

@test "scripts/bench.py: --help prints usage" {
	run uv run --script "$PROJECT_ROOT/scripts/bench.py" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"usage:"* ]]
	[[ "$output" == *"tool-turn"* ]]
}

@test "scripts/bench.py: tool-turn outputs json" {
	run uv run --script "$PROJECT_ROOT/scripts/bench.py" tool-turn --iterations 2
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.benchmark == "tool-turn"' > /dev/null
	echo "$output" | jq -e '.iterations == 2' > /dev/null
	echo "$output" | jq -e '.seconds >= 0' > /dev/null
}
