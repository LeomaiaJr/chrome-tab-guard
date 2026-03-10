#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.claude/hooks/lib.sh
source "$SCRIPT_DIR/lib.sh"

INPUT="$(cat)"
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name')"
INPUT_SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty')"
RESULT_BLOB="$(printf '%s' "$INPUT" | jq -r '[.tool_response?, .tool_error?, .stderr?, .error?, .message?] | map(select(. != null and . != "")) | join("\n")')"
SESSION_KEY="$(safe_session_key "$INPUT_SESSION_ID")"

if STATE_FILE="$(resolve_session_file "$INPUT_SESSION_ID" 2>/dev/null)"; then
  SESSION_KEY="$(state_field "$STATE_FILE" '.sessionKey')"
  CREATED_AT="$(state_field "$STATE_FILE" '.createdAt')"
  CURRENT_STATUS="$(state_field "$STATE_FILE" '.status')"
  CURRENT_TAB_ID="$(state_field "$STATE_FILE" '.tabId')"
else
  CREATED_AT=""
  CURRENT_STATUS="awaiting_tab"
  CURRENT_TAB_ID=""
fi

REPIN_MODE="${CHROME_REPIN_MODE:-latest}"

if [ "$TOOL_NAME" = "mcp__claude-in-chrome__tabs_create_mcp" ] && NEW_TAB_ID="$(extract_tab_id "$RESULT_BLOB" 2>/dev/null)"; then
  if [ "$REPIN_MODE" = "first" ] && [ "$CURRENT_STATUS" = "active" ] && [[ "$CURRENT_TAB_ID" =~ ^[0-9]+$ ]]; then
    log_debug "event=post_tool_capture_skipped key=$SESSION_KEY input_sid=${INPUT_SESSION_ID:-none} strategy=first current_tab=$CURRENT_TAB_ID new_tab=$NEW_TAB_ID"
    exit 0
  fi

  STATE_JSON="$(build_state_json "$SESSION_KEY" "$INPUT_SESSION_ID" "active" "$NEW_TAB_ID" "$TOOL_NAME" "" "$CREATED_AT")"
  write_state_json "$SESSION_KEY" "$INPUT_SESSION_ID" "$STATE_JSON"
  log_debug "event=post_tool_capture key=$SESSION_KEY input_sid=${INPUT_SESSION_ID:-none} tab=$NEW_TAB_ID strategy=$REPIN_MODE"
  exit 0
fi

if [ -n "$RESULT_BLOB" ] && is_stale_tab_error "$RESULT_BLOB"; then
  LAST_ERROR="$(printf '%s' "$RESULT_BLOB" | tr '\n' ' ' | cut -c1-300 | trim_whitespace)"
  STATE_JSON="$(build_state_json "$SESSION_KEY" "$INPUT_SESSION_ID" "stale" "$CURRENT_TAB_ID" "$TOOL_NAME" "$LAST_ERROR" "$CREATED_AT")"
  write_state_json "$SESSION_KEY" "$INPUT_SESSION_ID" "$STATE_JSON"
  log_debug "event=post_tool_stale key=$SESSION_KEY input_sid=${INPUT_SESSION_ID:-none} tab=${CURRENT_TAB_ID:-none} tool=${TOOL_NAME#mcp__claude-in-chrome__}"
  exit 0
fi

if [ "$CURRENT_STATUS" = "active" ] && [[ "$CURRENT_TAB_ID" =~ ^[0-9]+$ ]]; then
  STATE_JSON="$(build_state_json "$SESSION_KEY" "$INPUT_SESSION_ID" "active" "$CURRENT_TAB_ID" "$TOOL_NAME" "" "$CREATED_AT")"
  write_state_json "$SESSION_KEY" "$INPUT_SESSION_ID" "$STATE_JSON"
  log_debug "event=post_tool_ok key=$SESSION_KEY input_sid=${INPUT_SESSION_ID:-none} tab=$CURRENT_TAB_ID tool=${TOOL_NAME#mcp__claude-in-chrome__}"
fi

exit 0
