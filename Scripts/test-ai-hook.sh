#!/bin/bash
# Offline checks for Scripts/board-ai-hook: a temporary HOME, a stand-in process named Board, and the hook inputs in
# Tests/Fixtures (the PostToolUse shapes from Anthropic's hooks reference). Never touches the real Board folder.
set -euo pipefail
cd "$(dirname "$0")/.."
hook="$PWD/Scripts/board-ai-hook"
work="$(mktemp -d)"
board=""
trap '[ -n "$board" ] && kill "$board" 2>/dev/null; rm -rf "$work"' EXIT
queue="$work/home/Library/Application Support/Board/AI Queue"
run() { HOME="$work/home" "$hook" < "$1"; }
queued() { find "$queue" -name '*.txt' | wc -l | tr -d ' '; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# Board not running: no folder, no marker, nothing written, exit 0.
run Tests/Fixtures/hook-write.json || fail "exit status without Board"
[ ! -e "$queue" ] || fail "created the queue folder without Board"

# A marker naming a live process that isn't Board.
mkdir -p "$queue"; printf '%s' "$$" > "$queue/listening"
run Tests/Fixtures/hook-write.json
[ "$(queued)" = 0 ] || fail "wrote for a PID that isn't Board"

# Board running with AI mode on: Write's content and Edit's new_string arrive exactly.
printf '#include <unistd.h>\nint main(void){sleep(30);return 0;}\n' | cc -x c - -o "$work/Board"
"$work/Board" & board=$!
printf '%s' "$board" > "$queue/listening"
run Tests/Fixtures/hook-write.json
[ "$(queued)" = 1 ] || fail "Write text not queued"
expected="$(printf 'struct Greeting {\n    let name: String\n    func text() -> String { "Hello, \\(name)!" }\n}')"
[ "$(cat "$queue"/*.txt)" = "$expected" ] || fail "Write text differs: $(cat "$queue"/*.txt)"
rm -f "$queue"/*.txt
run Tests/Fixtures/hook-edit.json
expected="$(printf 'if name.isEmpty { return "Hi" }\n\treturn "Hello" // é ✓')"
[ "$(cat "$queue"/*.txt)" = "$expected" ] || fail "Edit text differs: $(cat "$queue"/*.txt)"
rm -f "$queue"/*.txt
# Codex: apply_patch's added lines arrive (its input contains nulls, which plutil couldn't read).
run Tests/Fixtures/hook-codex-patch.json
expected="$(printf 'def hello():\n    return "hi"\n    print(hello())')"
[ "$(cat "$queue"/*.txt)" = "$expected" ] || fail "Codex patch text differs: $(cat "$queue"/*.txt)"
rm -f "$queue"/*.txt
printf '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"transcript_path":null}' > "$work/bash.json"
run "$work/bash.json"
[ "$(queued)" = 0 ] || fail "queued a shell command as code"

# Large text is capped at 4 KB; input without text, or that isn't JSON, writes nothing.
big="$(head -c 10000 /dev/zero | tr '\0' 'x')"
printf '{"tool_name":"Write","tool_input":{"file_path":"/x","content":"%s"}}' "$big" > "$work/big.json"
run "$work/big.json"
[ "$(wc -c < "$queue"/*.txt | tr -d ' ')" = 4096 ] || fail "large text not capped at 4096 bytes"
rm -f "$queue"/*.txt
printf '{"tool_name":"Read","tool_input":{"file_path":"/x"}}' > "$work/none.json"
run "$work/none.json"
printf 'not json' > "$work/junk.json"
run "$work/junk.json"
[ "$(queued)" = 0 ] || fail "queued text for input without any"
[ -z "$(find "$queue" -name '.*.tmp')" ] || fail "left a temporary file"

# Board quit (stale marker): nothing written.
kill "$board"; wait "$board" 2>/dev/null || true; board=""
run Tests/Fixtures/hook-write.json
[ "$(queued)" = 0 ] || fail "wrote after Board quit"
echo "board-ai-hook: all checks passed"
