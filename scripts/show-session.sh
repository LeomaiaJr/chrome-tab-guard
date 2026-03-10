#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../.claude/hooks/lib.sh
source "$SCRIPT_DIR/../.claude/hooks/lib.sh"

INPUT_SESSION_ID="${1:-}"

if ! STATE_FILE="$(resolve_session_file "$INPUT_SESSION_ID" 2>/dev/null)"; then
  printf 'No session state found.\n' >&2
  exit 1
fi

cat "$STATE_FILE"
