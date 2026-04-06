#!/usr/bin/env bash
# api.sh — Anthropic API client with SSE streaming via FIFO pipe

MAX_RETRIES=3
CONSECUTIVE_529=0
JQ_SSE_PID=""

# Stream a request with automatic retry on rate limits
stream_request_with_retry() {
	local request_body="$1"
	local attempt=0
	local delay=1

	while ((attempt <= MAX_RETRIES)); do
		stream_request "$request_body"
		local status=$?

		if ((status == 0)); then
			CONSECUTIVE_529=0
			return 0
		fi

		# Check if it was a retryable error (rate limit)
		if ((status == 2)); then
			attempt=$((attempt + 1))
			if ((attempt > MAX_RETRIES)); then
				print_error "Max retries ($MAX_RETRIES) exceeded"
				return 1
			fi
			print_warning "Rate limited. Retrying in ${delay}s... (attempt $attempt/$MAX_RETRIES)"
			sleep "$delay"
			delay=$((delay * 2))
			# Restart spinner for retry
			start_spinner
		else
			return 1
		fi
	done
	return 1
}

# Stream a request to the Claude API and process events in real-time
# Returns: 0 on success, 1 on fatal error, 2 on retryable error (rate limit)
stream_request() {
	local request_body="$1"

	# Reset response state
	RESPONSE_CONTENT_BLOCKS="[]"
	RESPONSE_STOP_REASON=""
	RESPONSE_INPUT_TOKENS=0
	RESPONSE_OUTPUT_TOKENS=0
	RESPONSE_CACHE_READ=0
	RESPONSE_CACHE_WRITE=0

	# Temp files for accumulating state
	local blocks_file="$SESSION_DIR/blocks.json"
	local meta_file="$SESSION_DIR/meta.txt"
	local text_accum_file="$SESSION_DIR/text_accum.txt"
	local tool_json_file="$SESSION_DIR/tool_json_accum.txt"
	local current_block_file="$SESSION_DIR/current_block.json"

	echo '[]' >"$blocks_file"
	: >"$meta_file"
	: >"$text_accum_file"
	: >"$tool_json_file"
	: >"$current_block_file"

	local api_key="${ANTHROPIC_API_KEY}"
	local api_url="${ANTHROPIC_API_URL:-https://api.anthropic.com}"

	if [[ -z "$api_key" ]]; then
		print_error "ANTHROPIC_API_KEY not set"
		return 1
	fi

	stop_spinner

	# Create a FIFO for real-time streaming
	local fifo="$SESSION_DIR/sse_fifo"
	[[ -p "$fifo" ]] && rm -f "$fifo"
	mkfifo "$fifo"

	# Start persistent jq coprocess for SSE event processing
	# One long-running jq replaces all per-event jq forks (except content_block_stop)
	local jq_in_fifo="$SESSION_DIR/jq_sse_in"
	local jq_out_fifo="$SESSION_DIR/jq_sse_out"
	[[ -p "$jq_in_fifo" ]] && rm -f "$jq_in_fifo"
	[[ -p "$jq_out_fifo" ]] && rm -f "$jq_out_fifo"
	mkfifo "$jq_in_fifo" "$jq_out_fifo"

	jq --unbuffered -Rrj '
        (index("\t") // length) as $i | .[:$i] as $ev |
        (.[$i+1:] | if . == "" then {} else (try fromjson catch {}) end) as $d |
        if $ev == "message_start" then
            ($d.message.usage // {}) |
            "M\(.input_tokens // 0)\t\(.cache_read_input_tokens // 0)\t\(.cache_creation_input_tokens // 0)\u0000"
        elif $ev == "content_block_start" then
            ($d.content_block // {}) |
            "S\(.type // "")\t\(.name // "")\n\(tojson)\u0000"
        elif $ev == "content_block_delta" then
            ($d.delta // {}) |
            if .type == "text_delta" then "T\(.text // "")\u0000"
            elif .type == "input_json_delta" then "J\(.partial_json // "")\u0000"
            else "X\u0000" end
        elif $ev == "message_delta" then
            "D\($d.delta.stop_reason // "")\t\($d.usage.output_tokens // 0)\u0000"
        elif $ev == "error" then
            "E\($d.error.message // $d.message // "Unknown error")\u0000"
        else "X\u0000" end
    ' <"$jq_in_fifo" >"$jq_out_fifo" 2>/dev/null &
	JQ_SSE_PID=$!

	# Open FDs for coprocess communication (unblocks jq's FIFO opens)
	exec 7>"$jq_in_fifo"
	exec 8<"$jq_out_fifo"

	# Track curl's HTTP response code via a file
	local http_code_file="$SESSION_DIR/http_code"
	: >"$http_code_file"

	# Launch curl in background, writing SSE stream to the FIFO
	(
		local code
		code=$(curl -sS -w '%{http_code}' \
			--no-buffer \
			-o "$fifo" \
			-X POST "${api_url}/v1/messages" \
			-H "content-type: application/json" \
			-H "x-api-key: ${api_key}" \
			-H "anthropic-version: 2023-06-01" \
			-d "$request_body" 2>/dev/null)
		echo "$code" >"$http_code_file"
	) &
	local curl_pid=$!

	# Parse SSE events from the FIFO in real-time
	local current_event="" current_data=""

	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%$'\r'}"

		if [[ "$line" == event:* ]]; then
			current_event="${line#event: }"
		elif [[ "$line" == data:* ]]; then
			current_data="${line#data: }"
		elif [[ -z "$line" ]] && [[ -n "$current_event" ]]; then
			process_sse_event "$current_event" "$current_data" \
				"$blocks_file" "$text_accum_file" "$tool_json_file" \
				"$current_block_file" "$meta_file"
			current_event=""
			current_data=""
		fi
	done <"$fifo"

	# Shut down jq coprocess (closing write end triggers EOF → jq exits)
	exec 7>&-
	wait "$JQ_SSE_PID" 2>/dev/null
	exec 8<&-
	JQ_SSE_PID=""
	rm -f "$jq_in_fifo" "$jq_out_fifo"

	# Wait for curl to finish
	wait "$curl_pid" 2>/dev/null

	# Check HTTP status
	local http_code
	http_code=$(cat "$http_code_file" 2>/dev/null)

	if [[ -n "$http_code" ]] && [[ "$http_code" != "200" ]] && [[ "$http_code" != "000" ]]; then
		if [[ "$(cat "$blocks_file")" == "[]" ]]; then
			rm -f "$fifo"
			# Rate limit errors are retryable
			if [[ "$http_code" == "429" ]] || [[ "$http_code" == "529" ]]; then
				if [[ "$http_code" == "529" ]]; then
					CONSECUTIVE_529=$((CONSECUTIVE_529 + 1))
				fi
				return 2
			fi
			print_error "API returned HTTP $http_code"
			return 1
		fi
	fi

	rm -f "$fifo"

	# Read final state
	RESPONSE_CONTENT_BLOCKS=$(cat "$blocks_file")
	RESPONSE_STOP_REASON=$(grep '^stop_reason=' "$meta_file" 2>/dev/null | tail -1 | cut -d= -f2)
	RESPONSE_INPUT_TOKENS=$(grep '^input_tokens=' "$meta_file" 2>/dev/null | tail -1 | cut -d= -f2)
	RESPONSE_OUTPUT_TOKENS=$(grep '^output_tokens=' "$meta_file" 2>/dev/null | tail -1 | cut -d= -f2)
	RESPONSE_CACHE_READ=$(grep '^cache_read=' "$meta_file" 2>/dev/null | tail -1 | cut -d= -f2)
	RESPONSE_CACHE_WRITE=$(grep '^cache_write=' "$meta_file" 2>/dev/null | tail -1 | cut -d= -f2)

	RESPONSE_INPUT_TOKENS=${RESPONSE_INPUT_TOKENS:-0}
	RESPONSE_OUTPUT_TOKENS=${RESPONSE_OUTPUT_TOKENS:-0}
	RESPONSE_CACHE_READ=${RESPONSE_CACHE_READ:-0}
	RESPONSE_CACHE_WRITE=${RESPONSE_CACHE_WRITE:-0}
	RESPONSE_STOP_REASON=${RESPONSE_STOP_REASON:-end_turn}

	printf '\n'
}

# Process a single SSE event — called in real-time as events arrive
# Uses persistent jq coprocess when available (FDs 7/8), falls back to per-event forks
process_sse_event() {
	local event="$1" data="$2"
	local blocks_file="$3" text_accum_file="$4" tool_json_file="$5"
	local current_block_file="$6" meta_file="$7"

	# content_block_stop requires file-based jq (reads/writes accumulator files)
	if [[ "$event" == "content_block_stop" ]]; then
		local block
		block=$(cat "$current_block_file")

		if [[ "$block" == *'"text"'* ]]; then
			jq --rawfile text "$text_accum_file" \
				--argjson block "$block" \
				'. += [$block | .text = $text]' "$blocks_file" >"${blocks_file}.tmp" &&
				mv "${blocks_file}.tmp" "$blocks_file"
		elif [[ "$block" == *'"tool_use"'* ]]; then
			local tool_json
			tool_json=$(cat "$tool_json_file")
			jq --argjson block "$block" --arg raw "$tool_json" \
				'. += [$block | .input = ($raw | fromjson? // {})]' "$blocks_file" >"${blocks_file}.tmp" &&
				mv "${blocks_file}.tmp" "$blocks_file"
			printf '\n'
		fi
		return
	fi

	[[ "$event" == "message_stop" ]] && return

	# Fast path: persistent jq coprocess (zero fork overhead per event)
	if [[ -n "${JQ_SSE_PID:-}" ]]; then
		local result

		if ! printf '%s\t%s\n' "$event" "$data" >&7; then
			JQ_SSE_PID=""
		elif ! IFS= read -r -d '' result <&8; then
			JQ_SSE_PID=""
		else
			case "${result:0:1}" in
			M) # message_start: input_tokens\tcache_read\tcache_write
				local payload="${result:1}"
				{
					echo "input_tokens=${payload%%	*}"
					local rest="${payload#*	}"
					echo "cache_read=${rest%%	*}"
					echo "cache_write=${rest#*	}"
				} >>"$meta_file"
				;;
			S) # content_block_start: type\tname\nblock_json
				local payload="${result:1}"
				local header="${payload%%$'\n'*}"
				local block_json="${payload#*$'\n'}"
				local block_type="${header%%	*}"
				local tool_name="${header#*	}"

				echo "$block_json" >"$current_block_file"

				if [[ "$block_type" == "text" ]]; then
					: >"$text_accum_file"
				elif [[ "$block_type" == "tool_use" ]]; then
					: >"$tool_json_file"
					if [[ -n "$tool_name" ]]; then
						printf '\n%b  [calling %s...]%b' "$DIM" "$tool_name" "$RESET"
					fi
				fi
				;;
			T) # text_delta: stream to terminal and accumulate
				local payload="${result:1}"
				printf '%s' "$payload"
				printf '%s' "$payload" >>"$text_accum_file"
				;;
			J) # input_json_delta: accumulate tool input
				printf '%s' "${result:1}" >>"$tool_json_file"
				;;
			D) # message_delta: stop_reason\toutput_tokens
				local payload="${result:1}"
				{
					echo "stop_reason=${payload%%	*}"
					echo "output_tokens=${payload#*	}"
				} >>"$meta_file"
				;;
			E) # error
				print_error "Stream error: ${result:1}"
				;;
			esac
			return
		fi
	fi

	# Fallback: fork jq per event (used when coprocess is not running, e.g. tests)
	case "$event" in
	message_start)
		local usage_line
		usage_line=$(echo "$data" | jq -r '.message.usage | "\(.input_tokens // 0)\t\(.cache_read_input_tokens // 0)\t\(.cache_creation_input_tokens // 0)"' 2>/dev/null)
		{
			echo "input_tokens=${usage_line%%	*}"
			local rest="${usage_line#*	}"
			echo "cache_read=${rest%%	*}"
			echo "cache_write=${rest#*	}"
		} >>"$meta_file"
		;;

	content_block_start)
		local block_info block_type tool_name
		block_info=$(echo "$data" | jq -r '.content_block | "\(.type // "")\t\(.name // "")"' 2>/dev/null)
		block_type="${block_info%%	*}"
		tool_name="${block_info#*	}"

		if [[ "$block_type" == "text" ]]; then
			: >"$text_accum_file"
			echo "$data" | jq -c '.content_block' >"$current_block_file"
		elif [[ "$block_type" == "tool_use" ]]; then
			: >"$tool_json_file"
			echo "$data" | jq -c '.content_block' >"$current_block_file"
			if [[ -n "$tool_name" ]]; then
				printf '\n%b  [calling %s...]%b' "$DIM" "$tool_name" "$RESET"
			fi
		fi
		;;

	content_block_delta)
		if [[ "$data" == *'"text_delta"'* ]]; then
			local text
			text=$(echo "$data" | jq -r '.delta.text // empty' 2>/dev/null)
			printf '%s' "$text"
			printf '%s' "$text" >>"$text_accum_file"
		elif [[ "$data" == *'"input_json_delta"'* ]]; then
			local partial
			partial=$(echo "$data" | jq -r '.delta.partial_json // empty' 2>/dev/null)
			printf '%s' "$partial" >>"$tool_json_file"
		fi
		;;

	message_delta)
		local delta_line
		delta_line=$(echo "$data" | jq -r '"\(.delta.stop_reason // "")\t\(.usage.output_tokens // 0)"' 2>/dev/null)
		{
			echo "stop_reason=${delta_line%%	*}"
			echo "output_tokens=${delta_line#*	}"
		} >>"$meta_file"
		;;

	error)
		local error_msg
		error_msg=$(echo "$data" | jq -r '.error.message // .message // "Unknown error"' 2>/dev/null)
		print_error "Stream error: $error_msg"
		;;
	esac
}
