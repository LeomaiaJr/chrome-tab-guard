#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../.claude/hooks/lib.sh
source "$SCRIPT_DIR/../.claude/hooks/lib.sh"

SESSION_KEY="${CHROME_SESSION_KEY:-}"
INPUT_SESSION_ID=""
HARD_RESET=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --session-key)
      SESSION_KEY="${2:-}"
      shift 2
      ;;
    --session-id)
      INPUT_SESSION_ID="${2:-}"
      shift 2
      ;;
    --hard)
      HARD_RESET=1
      shift
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [ -n "$INPUT_SESSION_ID" ] && STATE_FILE="$(resolve_session_file "$INPUT_SESSION_ID" 2>/dev/null)"; then
  SESSION_KEY="$(state_field "$STATE_FILE" '.sessionKey')"
elif [ -z "$SESSION_KEY" ] && STATE_FILE="$(resolve_session_file "" 2>/dev/null)"; then
  SESSION_KEY="$(state_field "$STATE_FILE" '.sessionKey')"
fi

if [ -z "$SESSION_KEY" ]; then
  printf 'No session state found to reset.\n' >&2
  exit 1
fi

STATE_FILE="$(session_file_for_key "$SESSION_KEY")"
CREATED_AT=""
if [ -f "$STATE_FILE" ] && [ -s "$STATE_FILE" ]; then
  CREATED_AT="$(state_field "$STATE_FILE" '.createdAt')"
fi

if [ "$HARD_RESET" -eq 1 ]; then
  rm -f "$STATE_FILE"
  if [ -n "$INPUT_SESSION_ID" ] && [ -f "$(alias_file_for_sid "$INPUT_SESSION_ID")" ]; then
    rm -f "$(alias_file_for_sid "$INPUT_SESSION_ID")"
  fi
  log_debug "event=manual_reset_hard key=$SESSION_KEY input_sid=${INPUT_SESSION_ID:-none}"
  printf 'Removed session state for %s\n' "$SESSION_KEY"
  exit 0
fi

STATE_JSON="$(build_state_json "$SESSION_KEY" "$INPUT_SESSION_ID" "awaiting_tab" "" "manual_reset" "" "$CREATED_AT")"
write_state_json "$SESSION_KEY" "$INPUT_SESSION_ID" "$STATE_JSON"
log_debug "event=manual_reset key=$SESSION_KEY input_sid=${INPUT_SESSION_ID:-none}"
printf 'Reset session %s to awaiting_tab\n' "$SESSION_KEY"
