#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.claude/hooks/lib.sh
source "$SCRIPT_DIR/lib.sh"

INPUT="$(cat)"
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name')"
INPUT_SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty')"

case "$TOOL_NAME" in
  mcp__claude-in-chrome__tabs_context_mcp|mcp__claude-in-chrome__tabs_create_mcp)
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow"
      }
    }'
    exit 0
    ;;
esac

if ! STATE_FILE="$(resolve_session_file "$INPUT_SESSION_ID" 2>/dev/null)"; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "No Chrome tab is pinned for this session. Call tabs_create_mcp before using other browser tools."
    }
  }'
  exit 0
fi

SESSION_KEY="$(state_field "$STATE_FILE" '.sessionKey')"
STATUS="$(state_field "$STATE_FILE" '.status')"
TAB_ID="$(state_field "$STATE_FILE" '.tabId')"

write_alias "$INPUT_SESSION_ID" "$SESSION_KEY"

if [ "$STATUS" = "stale" ]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "The pinned Chrome tab for this session appears stale or closed. Call tabs_create_mcp to repin a fresh tab, or run ./scripts/reset-tab.sh to clear the session state manually."
    }
  }'
  exit 0
fi

if [ "$STATUS" != "active" ] || ! [[ "$TAB_ID" =~ ^[0-9]+$ ]]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "This session has not pinned a valid Chrome tab yet. Call tabs_create_mcp to create one."
    }
  }'
  exit 0
fi

TOOL_INPUT="$(printf '%s' "$INPUT" | jq '.tool_input // {}')"
UPDATED_INPUT="$(printf '%s' "$TOOL_INPUT" | jq --argjson tabId "$TAB_ID" '. + {tabId: $tabId}')"

log_debug "event=pre_tool_allow key=$SESSION_KEY input_sid=${INPUT_SESSION_ID:-none} tab=$TAB_ID tool=${TOOL_NAME#mcp__claude-in-chrome__}"

jq -n --argjson updated "$UPDATED_INPUT" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    updatedInput: $updated
  }
}'
