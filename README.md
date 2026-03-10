# Chrome Tab Guard

Claude Code hook scripts that keep concurrent Claude-in-Chrome sessions pinned
to their own Chrome tabs, with recovery support when a tab is closed or a
session needs to be repinned.

## What it does

- Creates a stable per-session key on startup
- Persists session state as JSON instead of a bare tab number
- Injects the pinned `tabId` into every `mcp__claude-in-chrome__*` tool call
- Detects common "tab closed / target gone" failures after tool execution
- Lets a session repin to a new tab after failure
- Provides helper scripts to reset and inspect session state

## Prerequisites

- Claude Code with the Claude-in-Chrome MCP server configured
- `jq`

## Hook layout

| File | Event | Purpose |
|------|-------|---------|
| `.claude/hooks/session-start.sh` | `SessionStart` | Creates a stable session key and writes an `awaiting_tab` state record |
| `.claude/hooks/enforce-tab-id.sh` | `PreToolUse` | Allows bootstrap tools and injects the pinned `tabId` into all other browser calls |
| `.claude/hooks/post-tool-use.sh` | `PostToolUse` | Captures new tab IDs, updates metadata, and marks stale tabs after tool failures |

Session state lives in `~/.claude/chrome-sessions/` by default:

- `sessions/<session-key>.json`
- `aliases/<hook-session-id>`
- `debug.log`

## Install into a project

```bash
mkdir -p .claude/hooks
cp .claude/hooks/lib.sh .claude/hooks/session-start.sh .claude/hooks/enforce-tab-id.sh .claude/hooks/post-tool-use.sh /path/to/your-project/.claude/hooks/
chmod +x /path/to/your-project/.claude/hooks/*.sh
```

Merge these hooks into your project's `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": ".claude/hooks/session-start.sh" }]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "mcp__claude-in-chrome__.*",
        "hooks": [{ "type": "command", "command": ".claude/hooks/enforce-tab-id.sh" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "mcp__claude-in-chrome__.*",
        "hooks": [{ "type": "command", "command": ".claude/hooks/post-tool-use.sh" }]
      }
    ]
  }
}
```

## Global install

Run:

```bash
./scripts/install.sh --global
```

That copies the hook files into `~/.claude/hooks/chrome-tab-guard/` and prints
the `settings.json` snippet you should merge into `~/.claude/settings.json`.

## Recovery flow

If you close the pinned tab by accident:

1. The next browser tool usually fails.
2. `post-tool-use.sh` marks the session state as `stale`.
3. `enforce-tab-id.sh` denies future browser calls with a recovery message.
4. Call `tabs_create_mcp` to create a replacement tab.
5. The new tab becomes the pinned tab for the session.

You can also reset a session manually:

```bash
./scripts/reset-tab.sh
```

To inspect the current session:

```bash
./scripts/show-session.sh
```

## Configuration

Optional environment variables:

- `CHROME_SESSION_DIR`: Override the state directory
- `CHROME_REPIN_MODE`: `latest` (default) or `first`
- `CHROME_DEBUG`: `1` to keep verbose debug logging enabled

`latest` means every successful `tabs_create_mcp` call becomes the new pinned
tab. `first` preserves the first tab until the state becomes `stale` or you
reset it manually.

## State model

Each session JSON file stores:

```json
{
  "version": 1,
  "sessionKey": "chrome-...",
  "inputSessionId": "abc123",
  "status": "active",
  "tabId": 42,
  "createdAt": "2026-03-10T15:00:00Z",
  "updatedAt": "2026-03-10T15:05:00Z",
  "lastToolName": "mcp__claude-in-chrome__navigate",
  "lastError": ""
}
```

## Development

Run the local test suite:

```bash
./scripts/test-hooks.sh
```

Run lint locally if you have `shellcheck`:

```bash
shellcheck .claude/hooks/*.sh scripts/*.sh
```

## Known limitations

- This isolates separate Claude Code sessions, not sub-agents inside one session
- Recovery depends on the browser tool surfacing a recognizable "tab gone"
  failure string
- Hooks can guide recovery, but they cannot create a replacement tab on their
  own; the session still needs to call `tabs_create_mcp`
