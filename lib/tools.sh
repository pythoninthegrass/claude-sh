#!/usr/bin/env bash
# tools.sh — Tool definitions and execution

# Build tools JSON array for the API
build_tools_json() {
	cat <<'TOOLS'
[
  {
    "name": "Bash",
    "description": "Executes a bash command and returns its output. Use for running shell commands, installing packages, running tests, git operations, etc.",
    "input_schema": {
      "type": "object",
      "properties": {
        "command": {
          "type": "string",
          "description": "The bash command to execute"
        },
        "description": {
          "type": "string",
          "description": "Short description of what this command does"
        },
        "timeout": {
          "type": "number",
          "description": "Timeout in seconds (default 30, max 300)"
        }
      },
      "required": ["command"]
    }
  },
  {
    "name": "Read",
    "description": "Reads a file and returns its contents with line numbers. Use to understand code before modifying it.",
    "input_schema": {
      "type": "object",
      "properties": {
        "file_path": {
          "type": "string",
          "description": "Absolute path to the file to read"
        },
        "offset": {
          "type": "number",
          "description": "Line number to start reading from (1-indexed)"
        },
        "limit": {
          "type": "number",
          "description": "Maximum number of lines to read (default 2000)"
        }
      },
      "required": ["file_path"]
    }
  },
  {
    "name": "Edit",
    "description": "Performs string replacement in a file. The old_string must match exactly (including whitespace/indentation). Read the file first.",
    "input_schema": {
      "type": "object",
      "properties": {
        "file_path": {
          "type": "string",
          "description": "Absolute path to the file to edit"
        },
        "old_string": {
          "type": "string",
          "description": "The exact string to find and replace"
        },
        "new_string": {
          "type": "string",
          "description": "The replacement string"
        }
      },
      "required": ["file_path", "old_string", "new_string"]
    }
  },
  {
    "name": "Write",
    "description": "Creates or overwrites a file with the given content. Use for creating new files.",
    "input_schema": {
      "type": "object",
      "properties": {
        "file_path": {
          "type": "string",
          "description": "Absolute path to the file to write"
        },
        "content": {
          "type": "string",
          "description": "The content to write to the file"
        }
      },
      "required": ["file_path", "content"]
    }
  },
  {
    "name": "Glob",
    "description": "Finds files matching a glob pattern. Returns file paths sorted by modification time.",
    "input_schema": {
      "type": "object",
      "properties": {
        "pattern": {
          "type": "string",
          "description": "Glob pattern (e.g. '**/*.ts', 'src/**/*.js')"
        },
        "path": {
          "type": "string",
          "description": "Directory to search in (default: cwd)"
        }
      },
      "required": ["pattern"]
    }
  },
  {
    "name": "Grep",
    "description": "Searches file contents using ripgrep. Supports regex patterns.",
    "input_schema": {
      "type": "object",
      "properties": {
        "pattern": {
          "type": "string",
          "description": "Regex pattern to search for"
        },
        "path": {
          "type": "string",
          "description": "File or directory to search in (default: cwd)"
        },
        "glob": {
          "type": "string",
          "description": "File pattern filter (e.g. '*.js')"
        },
        "case_insensitive": {
          "type": "boolean",
          "description": "Case insensitive search"
        }
      },
      "required": ["pattern"]
    }
  },
  {
    "name": "WebFetch",
    "description": "Fetches a specific URL and returns its content as readable text. HTML is converted to plain text. Use it after you already have a specific URL to inspect. Do not use it as a search substitute.",
    "input_schema": {
      "type": "object",
      "properties": {
        "url": {
          "type": "string",
          "description": "The URL to fetch"
        },
        "prompt": {
          "type": "string",
          "description": "Hint for what content to focus on"
        }
      },
      "required": ["url"]
    }
  },
  {
    "name": "WebSearch",
    "description": "Searches the web and returns results with titles, URLs, and snippets. Start with a single targeted search and only search again if the first results are clearly insufficient. Avoid repeated searches for the same question. Providers: Brave (BRAVE_API_KEY), Tavily (TAVILY_API_KEY), Ollama (OLLAMA_API_KEY), SearXNG (SEARXNG_URL), DuckDuckGo (fallback, may hit CAPTCHAs). Set CLAUDE_SH_SEARCH_PROVIDER to override auto-detection.",
    "input_schema": {
      "type": "object",
      "properties": {
        "query": {
          "type": "string",
          "description": "Search query"
        },
        "allowed_domains": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Only return results from these domains"
        },
        "blocked_domains": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Exclude results from these domains"
        }
      },
      "required": ["query"]
    }
  }
]
TOOLS
}

# Execute a tool by name
# Args: tool_name tool_id input_json
# Returns: tool result as JSON string
execute_tool() {
	local tool_name="$1"
	local tool_id="$2"
	local input_json="$3"
	local result=""
	local is_error=false

	case "$tool_name" in
	Bash) result=$(tool_bash "$input_json") ;;
	Read) result=$(tool_read "$input_json") ;;
	Edit) result=$(tool_edit "$input_json") ;;
	Write) result=$(tool_write "$input_json") ;;
	Glob) result=$(tool_glob "$input_json") ;;
	Grep) result=$(tool_grep "$input_json") ;;
	WebFetch) result=$(tool_webfetch "$input_json") ;;
	WebSearch) result=$(tool_websearch "$input_json") ;;
	*)
		result="Unknown tool: $tool_name"
		is_error=true
		;;
	esac

	local exit_code=$?
	if ((exit_code != 0)) && [[ "$is_error" == false ]]; then
		is_error=true
	fi

	tool_result_json "$tool_id" "$result" "$is_error"
}

parse_simple_object_fields() {
	local input_json="$1"
	shift

	local filter_parts=()
	local joined_filters=""
	local expr
	for expr in "$@"; do
		filter_parts+=("([($expr)] | if length == 0 then \"\" else .[0] end)")
	done

	local i
	for ((i = 0; i < ${#filter_parts[@]}; i++)); do
		[[ $i -gt 0 ]] && joined_filters+=', '
		joined_filters+="${filter_parts[$i]}"
	done

	printf '%s' "$input_json" | jq -j "[$joined_filters][] | tostring, \"\\u0000\"" 2>/dev/null
}

normalize_parsed_fields() {
	local -n parsed_fields_ref=$1
	:
}

tool_result_json() {
	local tool_id="$1"
	local result="$2"
	local is_error="${3:-false}"

	if [[ "$is_error" == "true" ]]; then
		jq -n \
			--arg id "$tool_id" \
			--arg content "$result" \
			'{"type": "tool_result", "tool_use_id": $id, "content": $content, "is_error": true}'
	else
		jq -n \
			--arg id "$tool_id" \
			--arg content "$result" \
			'{"type": "tool_result", "tool_use_id": $id, "content": $content}'
	fi
}

# ── Tool Implementations ──────────────────────────────────────

# Permission mode: "ask" (default), "allow" (trust all), "deny" (block writes)
PERMISSION_MODE="${CLAUDE_SH_PERMISSIONS:-ask}"

# Commands that are always safe (read-only)
is_safe_command() {
	local cmd="$1"
	local base_cmd
	base_cmd=$(echo "$cmd" | awk '{print $1}')

	# Check single-word commands first
	case "$base_cmd" in
	ls | cat | head | tail | wc | find | grep | rg | ag | \
		echo | printf | pwd | date | whoami | uname | env | which | \
		file | stat | du | df | tree | less | more | sort | uniq | diff | md5 | shasum | type)
		return 0
		;;
	esac

	# Check two-word commands (e.g. git subcommands)
	local two_words
	two_words=$(echo "$cmd" | awk '{print $1, $2}')
	case "$two_words" in
	"git log" | "git status" | "git diff" | "git show" | "git branch")
		return 0
		;;
	esac

	return 1
}

# Ask user for permission to run a command
ask_permission() {
	local command="$1"

	if [[ "$PERMISSION_MODE" == "allow" ]]; then
		return 0
	fi

	# Safe commands don't need permission in any mode
	if is_safe_command "$command"; then
		return 0
	fi

	if [[ "$PERMISSION_MODE" == "deny" ]]; then
		return 1
	fi

	# Interactive permission prompt
	printf '%b  Allow Bash:%b %s %b[y/n/a]%b ' "$YELLOW" "$RESET" "$command" "$DIM" "$RESET" >&2
	local answer
	read -rn1 answer </dev/tty
	printf '\n' >&2

	case "$answer" in
	y | Y) return 0 ;;
	a | A)
		PERMISSION_MODE="allow"
		return 0
		;;
	*) return 1 ;;
	esac
}

tool_bash() {
	local input="$1"
	local command timeout description
	local fields=()
	mapfile -d '' -t fields < <(parse_simple_object_fields "$input" '.command // empty' '(.timeout // 30 | tostring)' '.description // empty')
	normalize_parsed_fields fields
	command="${fields[0]}"
	timeout="${fields[1]}"
	description="${fields[2]}"

	if [[ -z "$command" ]]; then
		echo "Error: command is required"
		return 1
	fi

	# Cap timeout
	((timeout > 300)) && timeout=300

	# Display what we're running
	print_tool_header "Bash" "$description"
	printf '%b  $ %s%b\n' "$DIM" "$command" "$RESET"

	# Permission check (only in interactive mode)
	if [[ -t 0 ]]; then
		if ! ask_permission "$command"; then
			echo "Permission denied by user"
			return 1
		fi
	fi

	# Execute with timeout
	local output exit_code
	output=$(timeout "${timeout}s" bash -c "$command" 2>&1)
	exit_code=$?

	if ((exit_code == 124)); then
		output+=$'\n'"(timed out after ${timeout}s)"
	fi

	# Show truncated output
	if [[ -n "$output" ]]; then
		print_tool_output "$output" 30
	fi

	# Return full output (may be large)
	if ((exit_code != 0)); then
		printf '%s\n(exit code: %d)' "$output" "$exit_code"
		return 1
	else
		echo "$output"
	fi
}

tool_read() {
	local input="$1"
	local file_path offset limit
	local fields=()
	mapfile -d '' -t fields < <(parse_simple_object_fields "$input" '.file_path // empty' '(.offset // 1 | tostring)' '(.limit // 2000 | tostring)')
	normalize_parsed_fields fields
	file_path="${fields[0]}"
	offset="${fields[1]}"
	limit="${fields[2]}"

	if [[ -z "$file_path" ]]; then
		echo "Error: file_path is required"
		return 1
	fi

	# Expand ~ if present
	file_path="${file_path/#\~/$HOME}"

	if [[ ! -f "$file_path" ]]; then
		echo "Error: file not found: $file_path"
		return 1
	fi

	print_tool_header "Read" "$file_path"

	# Read with line numbers, respecting offset and limit
	local output
	output=$(cat -n "$file_path" | tail -n "+${offset}" | head -n "$limit")

	local total_lines
	total_lines=$(wc -l <"$file_path")
	local shown_lines
	shown_lines=$(echo "$output" | wc -l)

	print_dim "  ($shown_lines of $total_lines lines)"
	echo "$output"
}

tool_edit() {
	local input="$1"
	local file_path old_string new_string
	local fields=()
	mapfile -d '' -t fields < <(parse_simple_object_fields "$input" '.file_path // empty' '.old_string // empty' '.new_string // empty')
	normalize_parsed_fields fields
	file_path="${fields[0]}"
	old_string="${fields[1]}"
	new_string="${fields[2]}"

	if [[ -z "$file_path" ]] || [[ -z "$old_string" ]]; then
		echo "Error: file_path and old_string are required"
		return 1
	fi

	file_path="${file_path/#\~/$HOME}"

	if [[ ! -f "$file_path" ]]; then
		echo "Error: file not found: $file_path"
		return 1
	fi

	# Check if old_string exists in file
	if ! grep -qF "$old_string" "$file_path"; then
		echo "Error: old_string not found in $file_path"
		return 1
	fi

	# Count occurrences
	local count
	count=$(grep -cF "$old_string" "$file_path")
	if ((count > 1)); then
		echo "Error: old_string matches $count locations. Provide more context to make it unique."
		return 1
	fi

	print_tool_header "Edit" "$file_path"

	# Use python3 for reliable multiline string replacement
	python3 -c "
import sys, os
file_path, old_str, new_str = sys.argv[1], sys.argv[2], sys.argv[3]
with open(file_path, 'r') as f:
    content = f.read()
content = content.replace(old_str, new_str, 1)
with open(file_path, 'w') as f:
    f.write(content)
" "$file_path" "$old_string" "$new_string"

	print_success "  Edited successfully"
	echo "Edited $file_path: replaced 1 occurrence"
}

tool_write() {
	local input="$1"
	local file_path content
	local fields=()
	mapfile -d '' -t fields < <(parse_simple_object_fields "$input" '.file_path // empty' '.content // empty')
	normalize_parsed_fields fields
	file_path="${fields[0]}"
	content="${fields[1]}"

	if [[ -z "$file_path" ]]; then
		echo "Error: file_path is required"
		return 1
	fi

	file_path="${file_path/#\~/$HOME}"

	# Create parent dirs if needed
	mkdir -p "$(dirname "$file_path")"

	print_tool_header "Write" "$file_path"

	printf '%s' "$content" >"$file_path"

	local lines
	lines=$(echo "$content" | wc -l)
	print_success "  Wrote $lines lines"
	echo "Wrote $file_path ($lines lines)"
}

tool_glob() {
	local input="$1"
	local pattern search_path
	local fields=()
	mapfile -d '' -t fields < <(parse_simple_object_fields "$input" '.pattern // empty' '.path // empty')
	normalize_parsed_fields fields
	pattern="${fields[0]}"
	search_path="${fields[1]}"

	if [[ -z "$pattern" ]]; then
		echo "Error: pattern is required"
		return 1
	fi

	[[ -z "$search_path" ]] && search_path="."
	search_path="${search_path/#\~/$HOME}"

	print_tool_header "Glob" "$pattern"

	local output
	# Use find with glob pattern, exclude .git
	output=$(find "$search_path" -path '*/.git' -prune -o -name "$pattern" -print 2>/dev/null |
		head -n 100 | sort)

	# If simple glob doesn't work, try with bash globstar
	if [[ -z "$output" ]]; then
		output=$(cd "$search_path" && bash -O globstar -c "ls -1 $pattern 2>/dev/null" | head -n 100)
	fi

	local count
	count=$(echo "$output" | grep -c .)
	print_dim "  ($count files found)"
	echo "$output"
}

tool_grep() {
	local input="$1"
	local pattern search_path file_glob
	local case_insensitive
	local fields=()
	mapfile -d '' -t fields < <(parse_simple_object_fields "$input" '.pattern // empty' '.path // empty' '.glob // empty' '(.case_insensitive // false | tostring)')
	normalize_parsed_fields fields
	pattern="${fields[0]}"
	search_path="${fields[1]}"
	file_glob="${fields[2]}"
	case_insensitive="${fields[3]}"

	if [[ -z "$pattern" ]]; then
		echo "Error: pattern is required"
		return 1
	fi

	[[ -z "$search_path" ]] && search_path="."
	search_path="${search_path/#\~/$HOME}"

	print_tool_header "Grep" "$pattern"

	local args=("--no-heading" "--line-number" "--color=never")
	[[ "$case_insensitive" == "true" ]] && args+=("-i")
	[[ -n "$file_glob" ]] && args+=("--glob" "$file_glob")

	local output
	if command -v rg &>/dev/null; then
		output=$(rg "${args[@]}" "$pattern" "$search_path" 2>/dev/null | head -n 250)
	else
		# Fallback to grep
		local grep_args=("-rn" "--color=never")
		[[ "$case_insensitive" == "true" ]] && grep_args+=("-i")
		output=$(grep "${grep_args[@]}" "$pattern" "$search_path" 2>/dev/null | head -n 250)
	fi

	local count
	count=$(echo "$output" | grep -c . 2>/dev/null || echo 0)
	print_dim "  ($count matches)"
	echo "$output"
}

# ── WebFetch ─────────────────────────────────────────────────

# Convert HTML to plain text using python3 HTMLParser (stdlib)
_html_to_text() {
	if command -v python3 &>/dev/null; then
		python3 -c '
import sys
from html.parser import HTMLParser

class TextExtractor(HTMLParser):
    SKIP = {"script","style","nav","noscript"}
    BLOCK = {"p","div","br","li","tr","h1","h2","h3","h4","h5","h6","section","article"}
    def __init__(self):
        super().__init__()
        self._skip = 0
        self._text = []
    def handle_starttag(self, tag, attrs):
        if tag in self.SKIP: self._skip += 1
        elif tag in self.BLOCK: self._text.append("\n")
    def handle_endtag(self, tag):
        if tag in self.SKIP: self._skip = max(0, self._skip - 1)
        elif tag in self.BLOCK: self._text.append("\n")
    def handle_data(self, data):
        if not self._skip: self._text.append(data)

import re
p = TextExtractor()
p.feed(sys.stdin.read())
text = "".join(p._text)
text = re.sub(r"\n{3,}", "\n\n", text).strip()
print(text)
'
	else
		# Fallback: strip tags with sed
		sed -e 's/<script[^>]*>.*<\/script>//g' \
			-e 's/<style[^>]*>.*<\/style>//g' \
			-e 's/<[^>]*>//g' \
			-e '/^[[:space:]]*$/d'
	fi
}

tool_webfetch() {
	local input="$1"
	local url prompt
	local fields=()
	mapfile -d '' -t fields < <(parse_simple_object_fields "$input" '.url // empty' '.prompt // empty')
	normalize_parsed_fields fields
	url="${fields[0]}"
	prompt="${fields[1]}"

	if [[ -z "$url" ]]; then
		echo "Error: url is required"
		return 1
	fi

	print_tool_header "WebFetch" "$url"

	local tmpfile
	tmpfile=$(mktemp "${TMPDIR:-/tmp}/webfetch.XXXXXX")
	trap 'rm -f "$tmpfile"' RETURN

	# Fetch URL, capture content-type
	local content_type http_code
	content_type=$(curl -sS -L \
		--max-time 15 \
		--max-redirs 5 \
		--max-filesize 2097152 \
		-A "claude.sh/1.0" \
		-o "$tmpfile" \
		-w '%{content_type}\n%{http_code}' \
		"$url" 2>/dev/null) || {
		echo "Error: failed to fetch $url"
		return 1
	}

	http_code=$(echo "$content_type" | tail -1)
	content_type=$(echo "$content_type" | head -1)

	if ((http_code >= 400)); then
		echo "Error: HTTP $http_code fetching $url"
		return 1
	fi

	# Convert HTML to text, or pass through plain text
	local output
	if [[ "$content_type" == *"text/html"* ]]; then
		output=$(_html_to_text <"$tmpfile")
	else
		output=$(cat "$tmpfile")
	fi

	# Prepend prompt hint if provided
	if [[ -n "$prompt" ]]; then
		output="[User hint: $prompt]

$output"
	fi

	# Truncate to 20000 chars
	if ((${#output} > 20000)); then
		output="${output:0:20000}

[Content truncated at 20000 characters]"
	fi

	print_dim "  (${#output} chars)"
	echo "$output"
}

# ── WebSearch ────────────────────────────────────────────────

_websearch_brave() {
	local query="$1"

	if [[ -z "${BRAVE_API_KEY:-}" ]]; then
		echo "Error: BRAVE_API_KEY is required. Get a free key at https://brave.com/search/api/"
		return 1
	fi

	local encoded
	encoded=$(jq -rn --arg q "$query" '$q|@uri')

	local response
	response=$(curl -sS --max-time 10 \
		-H "Accept: application/json" \
		-H "Accept-Encoding: identity" \
		-H "X-Subscription-Token: $BRAVE_API_KEY" \
		"https://api.search.brave.com/res/v1/web/search?q=${encoded}&count=10" 2>/dev/null) || {
		echo "Error: Brave Search API request failed"
		return 1
	}

	local results
	results=$(echo "$response" | jq -r '.web.results[]? | "## \(.title)\n\(.url)\n\(.description // "")\n"' 2>/dev/null)

	if [[ -z "$results" ]]; then
		local api_error
		api_error=$(echo "$response" | jq -r '.message // .error // empty' 2>/dev/null)
		if [[ -n "$api_error" ]]; then
			echo "Error: Brave API: $api_error"
			return 1
		fi
		echo "No results found."
		return 0
	fi

	echo "$results"
}

_websearch_tavily() {
	local query="$1"

	if [[ -z "${TAVILY_API_KEY:-}" ]]; then
		echo "Error: TAVILY_API_KEY is required. Get a free key at https://tavily.com/"
		return 1
	fi

	local body
	body=$(jq -n --arg q "$query" --arg k "$TAVILY_API_KEY" \
		'{api_key: $k, query: $q, max_results: 10}')

	local response
	response=$(curl -sS --max-time 10 \
		-X POST \
		-H "Content-Type: application/json" \
		-d "$body" \
		"https://api.tavily.com/search" 2>/dev/null) || {
		echo "Error: Tavily API request failed"
		return 1
	}

	local results
	results=$(echo "$response" | jq -r '.results[]? | "## \(.title)\n\(.url)\n\(.content // "")\n"' 2>/dev/null)

	if [[ -z "$results" ]]; then
		echo "No results found."
		return 0
	fi

	echo "$results"
}

_websearch_searxng() {
	local query="$1"

	if [[ -z "${SEARXNG_URL:-}" ]]; then
		echo "Error: SEARXNG_URL is required (e.g. http://localhost:8080)"
		return 1
	fi

	local encoded
	encoded=$(jq -rn --arg q "$query" '$q|@uri')

	local response
	response=$(curl -sS --max-time 10 \
		"${SEARXNG_URL}/search?q=${encoded}&format=json" 2>/dev/null) || {
		echo "Error: SearXNG request failed"
		return 1
	}

	local results
	results=$(echo "$response" | jq -r '.results[:10][]? | "## \(.title)\n\(.url)\n\(.content // "")\n"' 2>/dev/null)

	if [[ -z "$results" ]]; then
		echo "No results found."
		return 0
	fi

	echo "$results"
}

# Parse DuckDuckGo HTML results using python3
_parse_ddg_results() {
	if command -v python3 &>/dev/null; then
		python3 -c '
import sys, re
from urllib.parse import unquote
from html.parser import HTMLParser

class DDGParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.results = []
        self._in_result_a = False
        self._in_snippet = False
        self._current = {}
        self._text = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        cls = attrs.get("class", "")
        if tag == "a" and "result__a" in cls:
            self._in_result_a = True
            self._text = []
            href = attrs.get("href", "")
            # Decode DuckDuckGo redirect
            m = re.search(r"uddg=([^&]+)", href)
            if m:
                self._current["url"] = unquote(m.group(1))
            else:
                url = href.lstrip("/")
                if not url.startswith("http"):
                    url = "https://" + url
                self._current["url"] = url
        elif tag == "a" and "result__snippet" in cls:
            self._in_snippet = True
            self._text = []

    def handle_endtag(self, tag):
        if tag == "a" and self._in_result_a:
            self._in_result_a = False
            self._current["title"] = "".join(self._text).strip()
        elif tag == "a" and self._in_snippet:
            self._in_snippet = False
            self._current["snippet"] = "".join(self._text).strip()
            if self._current.get("title") and self._current.get("url"):
                self.results.append(dict(self._current))
            self._current = {}

    def handle_data(self, data):
        if self._in_result_a or self._in_snippet:
            self._text.append(data)

html = sys.stdin.read()
p = DDGParser()
p.feed(html)
for r in p.results[:10]:
    t, u, s = r.get("title",""), r.get("url",""), r.get("snippet","")
    print("## " + t)
    print(u)
    print(s)
    print()
'
	else
		# Fallback: basic grep/sed extraction
		grep -o 'class="result__a" href="[^"]*">[^<]*' |
			head -10 |
			sed 's/class="result__a" href="//;s/">/\n/;s/^/## /'
	fi
}

_websearch_duckduckgo() {
	local query="$1"

	local encoded
	encoded=$(jq -rn --arg q "$query" '$q|@uri')

	local response
	response=$(curl -sS --max-time 10 \
		-A "claude.sh/1.0" \
		"https://html.duckduckgo.com/html/?q=${encoded}" 2>/dev/null) || {
		echo "Error: DuckDuckGo request failed"
		return 1
	}

	# Detect CAPTCHA/anti-bot challenge
	if echo "$response" | grep -q 'challenge-form\|anomaly'; then
		echo "Error: DuckDuckGo returned a CAPTCHA challenge. Configure an API-based provider instead:
  export OLLAMA_API_KEY=...  # ollama signin (free with account)
  export BRAVE_API_KEY=...   # https://brave.com/search/api/ (free: 2000/month)
  export TAVILY_API_KEY=...  # https://tavily.com/ (free: 1000/month)
  export SEARXNG_URL=...     # self-hosted SearXNG instance"
		return 1
	fi

	local results
	results=$(echo "$response" | _parse_ddg_results)

	if [[ -z "$results" ]]; then
		echo "No results found."
		return 0
	fi

	echo "$results"
}

_websearch_ollama() {
	local query="$1"

	if [[ -z "${OLLAMA_API_KEY:-}" ]]; then
		echo "Error: OLLAMA_API_KEY is required. Run 'ollama signin' or set it from https://ollama.com/settings/keys"
		return 1
	fi

	local response
	response=$(curl -sS --max-time 10 \
		-X POST \
		-H "Authorization: Bearer $OLLAMA_API_KEY" \
		-H "Content-Type: application/json" \
		-d "$(jq -n --arg q "$query" '{query: $q}')" \
		"https://ollama.com/api/web_search" 2>/dev/null) || {
		echo "Error: Ollama web search request failed"
		return 1
	}

	local results
	results=$(echo "$response" | jq -r '.results[]? | "## \(.title // "")\n\(.url // "")\n\(.content // .snippet // "")\n"' 2>/dev/null)

	if [[ -z "$results" ]]; then
		local api_error
		api_error=$(echo "$response" | jq -r '.error // empty' 2>/dev/null)
		if [[ -n "$api_error" ]]; then
			echo "Error: Ollama API: $api_error"
			return 1
		fi
		echo "No results found."
		return 0
	fi

	echo "$results"
}

# Detect search provider from env vars
_detect_search_provider() {
	if [[ -n "${CLAUDE_SH_SEARCH_PROVIDER:-}" ]]; then
		echo "$CLAUDE_SH_SEARCH_PROVIDER"
	elif [[ -n "${BRAVE_API_KEY:-}" ]]; then
		echo "brave"
	elif [[ -n "${TAVILY_API_KEY:-}" ]]; then
		echo "tavily"
	elif [[ -n "${OLLAMA_API_KEY:-}" ]]; then
		echo "ollama"
	elif [[ -n "${SEARXNG_URL:-}" ]]; then
		echo "searxng"
	else
		echo "duckduckgo"
	fi
}

tool_websearch() {
	local input="$1"

	# Single jq extracts query + domain lists (was 3 separate jq calls)
	local fields=() query allowed_domains blocked_domains
	mapfile -d '' -t fields < <(parse_simple_object_fields "$input" '.query // empty' '(.allowed_domains // []) | join("\n")' '(.blocked_domains // []) | join("\n")')
	normalize_parsed_fields fields
	query="${fields[0]}"
	allowed_domains="${fields[1]}"
	blocked_domains="${fields[2]}"

	if [[ -z "$query" ]]; then
		echo "Error: query is required"
		return 1
	fi

	if [[ -n "$allowed_domains" ]]; then
		local site_filter=""
		while IFS= read -r domain; do
			[[ -n "$site_filter" ]] && site_filter+=" OR "
			site_filter+="site:${domain}"
		done <<<"$allowed_domains"
		query="$query $site_filter"
	fi

	if [[ -n "$blocked_domains" ]]; then
		while IFS= read -r domain; do
			query="$query -site:${domain}"
		done <<<"$blocked_domains"
	fi

	local provider
	provider=$(_detect_search_provider)

	print_tool_header "WebSearch" "$query ($provider)"

	local results
	case "$provider" in
	brave) results=$(_websearch_brave "$query") ;;
	tavily) results=$(_websearch_tavily "$query") ;;
	searxng) results=$(_websearch_searxng "$query") ;;
	duckduckgo) results=$(_websearch_duckduckgo "$query") ;;
	ollama) results=$(_websearch_ollama "$query") ;;
	*)
		echo "Error: unknown search provider '$provider'. Use: brave, tavily, ollama, searxng, duckduckgo"
		return 1
		;;
	esac

	local exit_code=$?
	if ((exit_code != 0)); then
		echo "$results"
		return 1
	fi

	local count
	count=$(echo "$results" | grep -c '^## ' 2>/dev/null || echo 0)
	print_dim "  ($count results)"
	echo "$results"
}
