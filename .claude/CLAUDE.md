# Chrome Tab Guard

Browser isolation is enforced by hooks.

Rules:

1. Before browser work, call `tabs_context_mcp` and then `tabs_create_mcp`.
2. Never pass `tabId` manually.
3. If a browser tool is denied because the pinned tab is stale, create a new
   tab with `tabs_create_mcp`.
4. If recovery is stuck, reset the session with `./scripts/reset-tab.sh`.

The hooks are authoritative. If your browser calls conflict with these rules,
the hooks win.
