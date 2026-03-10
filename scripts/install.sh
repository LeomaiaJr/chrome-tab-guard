#!/usr/bin/env bash
set -euo pipefail

TARGET_MODE="${1:-}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$TARGET_MODE" = "--global" ]; then
  TARGET_DIR="$HOME/.claude/hooks/chrome-tab-guard"
  mkdir -p "$TARGET_DIR"
  cp "$PROJECT_ROOT/.claude/hooks/lib.sh" \
    "$PROJECT_ROOT/.claude/hooks/session-start.sh" \
    "$PROJECT_ROOT/.claude/hooks/enforce-tab-id.sh" \
    "$PROJECT_ROOT/.claude/hooks/post-tool-use.sh" \
    "$TARGET_DIR/"
  chmod +x "$TARGET_DIR/"*.sh

  cat <<EOF
Merge this into ~/.claude/settings.json:

{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "\$HOME/.claude/hooks/chrome-tab-guard/session-start.sh" }]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "mcp__claude-in-chrome__.*",
        "hooks": [{ "type": "command", "command": "\$HOME/.claude/hooks/chrome-tab-guard/enforce-tab-id.sh" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "mcp__claude-in-chrome__.*",
        "hooks": [{ "type": "command", "command": "\$HOME/.claude/hooks/chrome-tab-guard/post-tool-use.sh" }]
      }
    ]
  }
}
EOF
  exit 0
fi

cat <<EOF
Usage:
  ./scripts/install.sh --global
EOF
exit 1
