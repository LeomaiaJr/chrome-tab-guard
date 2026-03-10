#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

export HOME="$TMP_HOME"

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"

  if [ "$actual" != "$expected" ]; then
    printf 'FAIL: %s\nExpected: %s\nActual:   %s\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_contains() {
  local blob="$1"
  local expected="$2"
  local message="$3"

  if ! printf '%s' "$blob" | grep -Fq "$expected"; then
    printf 'FAIL: %s\nExpected to contain: %s\nActual: %s\n' "$message" "$expected" "$blob" >&2
    exit 1
  fi
}

chmod +x .claude/hooks/*.sh scripts/*.sh

ENV_FILE="$(mktemp)"
SESSION_START_RESULT="$(printf '%s' '{"session_id":"sid-start","source":"startup","hook_event_name":"SessionStart"}' | CLAUDE_ENV_FILE="$ENV_FILE" .claude/hooks/session-start.sh)"
SESSION_KEY="$(cut -d= -f2 "$ENV_FILE")"
assert_contains "$SESSION_START_RESULT" "CHROME TAB GUARD ACTIVE" "session-start should inject context"

STATE_FILE="$HOME/.claude/chrome-sessions/sessions/$SESSION_KEY.json"
assert_eq "$(jq -r '.status' "$STATE_FILE")" "awaiting_tab" "startup state should be awaiting_tab"

DENY_RESULT="$(printf '%s' '{"tool_name":"mcp__claude-in-chrome__navigate","tool_input":{"url":"https://example.com"},"session_id":"sid-start","hook_event_name":"PreToolUse"}' | CHROME_SESSION_KEY="$SESSION_KEY" .claude/hooks/enforce-tab-id.sh)"
assert_eq "$(printf '%s' "$DENY_RESULT" | jq -r '.hookSpecificOutput.permissionDecision')" "deny" "enforce should deny before tab creation"

printf '%s' '{"tool_name":"mcp__claude-in-chrome__tabs_create_mcp","tool_input":{},"tool_response":"{\"tabId\":42}","session_id":"sid-start","hook_event_name":"PostToolUse"}' | CHROME_SESSION_KEY="$SESSION_KEY" .claude/hooks/post-tool-use.sh
assert_eq "$(jq -r '.status' "$STATE_FILE")" "active" "tab creation should activate session"
assert_eq "$(jq -r '.tabId' "$STATE_FILE")" "42" "tab creation should capture tab id"

ALLOW_RESULT="$(printf '%s' '{"tool_name":"mcp__claude-in-chrome__navigate","tool_input":{"url":"https://example.com"},"session_id":"sid-start","hook_event_name":"PreToolUse"}' | CHROME_SESSION_KEY="$SESSION_KEY" .claude/hooks/enforce-tab-id.sh)"
assert_eq "$(printf '%s' "$ALLOW_RESULT" | jq -r '.hookSpecificOutput.permissionDecision')" "allow" "enforce should allow after tab creation"
assert_eq "$(printf '%s' "$ALLOW_RESULT" | jq -r '.hookSpecificOutput.updatedInput.tabId')" "42" "enforce should inject pinned tab id"

printf '%s' '{"tool_name":"mcp__claude-in-chrome__navigate","tool_input":{"url":"https://example.com"},"tool_response":"Error: target closed","session_id":"sid-start","hook_event_name":"PostToolUse"}' | CHROME_SESSION_KEY="$SESSION_KEY" .claude/hooks/post-tool-use.sh
assert_eq "$(jq -r '.status' "$STATE_FILE")" "stale" "closed tab error should mark state stale"

STALE_RESULT="$(printf '%s' '{"tool_name":"mcp__claude-in-chrome__navigate","tool_input":{"url":"https://example.com"},"session_id":"sid-start","hook_event_name":"PreToolUse"}' | CHROME_SESSION_KEY="$SESSION_KEY" .claude/hooks/enforce-tab-id.sh)"
assert_contains "$STALE_RESULT" "stale or closed" "stale state should produce recovery guidance"

printf '%s' '{"tool_name":"mcp__claude-in-chrome__tabs_create_mcp","tool_input":{},"tool_response":"Created new tab. Tab ID: 99","session_id":"sid-start","hook_event_name":"PostToolUse"}' | CHROME_SESSION_KEY="$SESSION_KEY" .claude/hooks/post-tool-use.sh
assert_eq "$(jq -r '.status' "$STATE_FILE")" "active" "repin should reactivate session"
assert_eq "$(jq -r '.tabId' "$STATE_FILE")" "99" "repin should replace stale tab id"

RESET_OUTPUT="$(CHROME_SESSION_KEY="$SESSION_KEY" ./scripts/reset-tab.sh)"
assert_contains "$RESET_OUTPUT" "awaiting_tab" "reset helper should move state back to awaiting_tab"
assert_eq "$(jq -r '.status' "$STATE_FILE")" "awaiting_tab" "reset should clear active tab"

printf 'All hook tests passed.\n'
