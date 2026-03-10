#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.claude/hooks/lib.sh
source "$SCRIPT_DIR/lib.sh"

INPUT="$(cat)"
SOURCE_NAME="$(printf '%s' "$INPUT" | jq -r '.source // "startup"')"
INPUT_SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty')"

ensure_state_layout
prune_stale_state

case "$SOURCE_NAME" in
  startup|clear)
    SESSION_KEY="$(generate_session_key)"
    STATE_JSON="$(build_state_json "$SESSION_KEY" "$INPUT_SESSION_ID" "awaiting_tab" "" "session_start" "" "")"
    write_state_json "$SESSION_KEY" "$INPUT_SESSION_ID" "$STATE_JSON"

    if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
      printf 'CHROME_SESSION_KEY=%s\n' "$SESSION_KEY" >> "$CLAUDE_ENV_FILE"
    fi
    ;;
  resume|compact)
    SESSION_KEY="$(safe_session_key "$INPUT_SESSION_ID")"
    if SESSION_FILE="$(resolve_session_file "$INPUT_SESSION_ID" 2>/dev/null)"; then
      write_alias "$INPUT_SESSION_ID" "$(state_field "$SESSION_FILE" '.sessionKey')"
    else
      STATE_JSON="$(build_state_json "$SESSION_KEY" "$INPUT_SESSION_ID" "awaiting_tab" "" "session_resume" "" "")"
      write_state_json "$SESSION_KEY" "$INPUT_SESSION_ID" "$STATE_JSON"
    fi
    ;;
  *)
    SESSION_KEY="$(safe_session_key "$INPUT_SESSION_ID")"
    if ! resolve_session_file "$INPUT_SESSION_ID" >/dev/null 2>&1; then
      STATE_JSON="$(build_state_json "$SESSION_KEY" "$INPUT_SESSION_ID" "awaiting_tab" "" "session_start" "" "")"
      write_state_json "$SESSION_KEY" "$INPUT_SESSION_ID" "$STATE_JSON"
    fi
    ;;
esac

log_debug "event=session_start source=$SOURCE_NAME key=${SESSION_KEY:-unknown} input_sid=${INPUT_SESSION_ID:-none}"

jq -n '{
  additionalContext: "CHROME TAB GUARD ACTIVE: Before browser automation, call tabs_context_mcp and then tabs_create_mcp. Do not pass tabId manually. If the pinned tab becomes stale or is closed, create a new tab with tabs_create_mcp or reset the session with ./scripts/reset-tab.sh."
}'
