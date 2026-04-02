# Plan: cmux Workspace Provider Extension System

## Current Status

All planned features are implemented.

| Phase | Status |
|-------|--------|
| Extension Protocol | ✅ |
| "+" Dropdown + Provider Integration | ✅ |
| Simple Non-Worktree Project | ✅ |
| Suspended Tabs | ✅ |
| Worktree Support | ✅ |
| Workflows | ✅ |
| Pending Workspace + Progress | ✅ |
| Live Terminal Setup | ✅ |
| Destroy on Close | ✅ |
| Session Restore (Suspended) | ✅ |
| Context Menu (Stop/Delete) | ✅ |

---

## Overview

An extension point in cmux so external tools can inject items into the workspace creation flow. The "+" button in the titlebar shows a dropdown: "New Workspace" (default) plus items from registered providers. Clicking a provider item runs the provider's setup flow in a live terminal and creates a workspace from its output.

cmux doesn't know about git, worktrees, or workflows. It just calls the provider and gets back a workspace definition.

## Extension Protocol

### Configuration

In `~/.config/cmux/cmux.json`:

```json
{
  "workspace_providers": [
    {
      "id": "cmux-worktree",
      "name": "Projects",
      "list": "cmux-worktree list",
      "create": "cmux-worktree create",
      "destroy": "cmux-worktree destroy",
      "isolate_browser": true
    }
  ]
}
```

Per-project `.cmux/cmux.json` can also define providers (merged with global).

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique ID for the provider |
| `name` | string | Display name (shown in menu header) |
| `list` | string | Shell command that outputs JSON list of items |
| `create` | string | Shell command that runs in a live terminal |
| `destroy` | string? | Shell command called when a provider workspace is deleted |
| `isolate_browser` | bool? | When true, each workspace gets its own browser storage (cookies, localStorage). Default: false (shared across workspaces). |

### Protocol

#### `list` command

Called on hover over "+" (with 10s TTL cache). Must respond quickly (<2s).

```json
{
  "items": [
    {
      "id": "my-project::blank",
      "name": "My Project — Blank",
      "subtitle": "~/workspace/my-project",
      "inputs": [
        {
          "id": "session",
          "label": "Session Name",
          "placeholder": "e.g. fix login bug",
          "required": true
        },
        {
          "id": "branch",
          "label": "Branch Name",
          "placeholder": "auto-generated from session name",
          "required": false,
          "deriveFrom": "session"
        }
      ]
    },
    {
      "id": "simple-project",
      "name": "Simple Project",
      "subtitle": "~/workspace/simple"
    }
  ]
}
```

- `inputs` is optional. If present, cmux shows a floating input panel (NSPanel) before calling `create`.
- `deriveFrom` auto-fills a field by slugifying another field's value. User can override.
- Items with no `inputs` create the workspace immediately on click.

#### `create` command

Runs in a live terminal so the user can watch setup in real time. cmux sets `CMUX_PROVIDER_OUTPUT` env var to a temp file path. The provider writes the workspace definition JSON to that file on success.

```bash
CMUX_PROVIDER_OUTPUT=/tmp/cmux-provider-xxx.json provider create --id my-project::blank --input session=feature-x --input branch=feature-x
```

All stdout/stderr goes to the terminal naturally — no special protocol needed.

**On success:** provider writes JSON to `$CMUX_PROVIDER_OUTPUT`, cmux reads it and applies the layout (closes setup terminal, creates configured tabs/splits).

**On failure:** provider exits with non-zero, no output file written. User is left in the terminal to investigate.

**Workspace definition format:**

```json
{
  "title": "feature-x · My Project",
  "cwd": "/Users/me/.cmux/workspaces/my-project/feature-x",
  "color": "#3498DB",
  "env": {
    "CMUX_PROVIDER_PROJECT": "my-project",
    "CMUX_PROVIDER_WORKFLOW": "Blank",
    "CMUX_PROVIDER_SESSION": "feature-x",
    "CMUX_PROVIDER_BRANCH": "feature-x"
  },
  "layout": {
    "direction": "horizontal",
    "split": 0.6,
    "children": [
      {
        "pane": {
          "surfaces": [
            { "type": "terminal", "name": "Shell" },
            { "type": "terminal", "name": "Git", "command": "lazygit", "suspended": true }
          ]
        }
      },
      {
        "pane": {
          "surfaces": [
            { "type": "terminal", "name": "Dev", "command": "bun run dev", "suspended": true }
          ]
        }
      }
    ]
  }
}
```

#### `destroy` command

Called when a provider workspace is **deleted** (via context menu "Delete Workspace"). Runs async in background. NOT called on regular close or stop.

```bash
provider destroy --id my-project::blank --cwd /path/to/worktree --input session=feature-x --input branch=feature-x
```

Used for cleanup: removing git worktrees, freeing ports, etc. Failures are logged but don't block the UI.

### Surface options

| Field | Type | Description |
|-------|------|-------------|
| `type` | `"terminal"` or `"browser"` | Surface type |
| `name` | string? | Tab name |
| `command` | string? | Command to run (terminal only) |
| `cwd` | string? | Working directory override |
| `env` | object? | Per-surface environment variables |
| `url` | string? | URL to load (browser only) |
| `focus` | bool? | Focus this surface on creation |
| `suspended` | bool? | Show "Press Enter to run" loop instead of auto-executing |
| `wait_for` | string? | Shell command that must exit 0 before a browser surface loads its URL. Polled with exponential backoff (1s → 10s cap). |

### wait_for (browser readiness check)

Browser surfaces with `wait_for` start blank and poll a shell command with exponential backoff (1s → 2s → 4s → 8s → 10s cap). The URL loads once the command exits 0.

```json
{
  "type": "browser",
  "name": "Preview",
  "url": "http://localhost:3000",
  "wait_for": "curl -sf http://localhost:3000 > /dev/null"
}
```

Useful for dev server previews — the browser waits until the server is ready instead of showing an error page.

### Suspended mode

When `suspended: true` and `command` is set, the terminal shows a clean screen with:

```
▶ Press Enter to run: lazygit
```

Pressing Enter runs the command. When the command exits (Ctrl-C, crash, or normal quit), the screen clears and the prompt returns. Press Enter to re-run.

### Input field options

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Field identifier (passed as `--input id=value`) |
| `label` | string | Display label |
| `placeholder` | string? | Placeholder text |
| `required` | bool? | Whether the field must be filled |
| `deriveFrom` | string? | Auto-fill by slugifying another field's value |

## UX Flow

### Creating a workspace

```
User hovers "+" in titlebar
  → Provider items pre-fetched in background (10s TTL cache)

User clicks "+"
  → NSMenu appears below the button:
      ┌──────────────────────┐
      │ New Workspace        │  ← default
      │ ──────────────────── │
      │ Projects             │  ← provider name (header)
      │   cmux — Blank       │
      │   cmux — From PR     │
      │   cmux — Dev Session │
      └──────────────────────┘

User clicks "cmux — Blank"
  → Input panel appears (NSPanel):
      ┌──────────────────────────┐
      │ cmux — Blank             │
      │                          │
      │ Session Name *           │
      │ ┌──────────────────────┐ │
      │ │ fix login bug        │ │
      │ └──────────────────────┘ │
      │ Branch Name              │
      │ ┌──────────────────────┐ │
      │ │ fix-login-bug        │ │  ← auto-derived, editable
      │ └──────────────────────┘ │
      │                          │
      │        Cancel   Create   │
      └──────────────────────────┘

User clicks Create
  → Workspace appears with a live setup terminal
  → User watches git worktree creation, dependency install, etc.
  → On success (output file written) → setup terminal replaced with configured layout
  → On failure (non-zero exit) → user is in the terminal to investigate
```

### Workspace lifecycle

Provider workspaces have three context menu actions:

- **Stop** — suspends the workspace: tears down all terminals, dims in sidebar (40% opacity), frees resources. Click to re-activate.
- **Delete Workspace** — confirmation dialog → calls provider `destroy` command (removes git worktree) → closes workspace.
- **Activate** (shown on suspended workspaces) — re-creates terminals and runs commands.

Regular "Close Workspace" and the X button are **hidden** for provider workspaces to avoid ambiguity. Use Stop or Delete instead.

### Session restore

- Provider workspaces persist `providerOrigin` and `suspendedLayout` in the session snapshot.
- On app restart, provider workspaces restore as **suspended** (dimmed, no terminals).
- The previously selected workspace is only restored if it's not suspended; otherwise the first non-suspended workspace is selected.
- If all workspaces are suspended, a fresh default workspace is created.
- Click a suspended workspace to activate it.

## cmux Implementation

### Files

- `Sources/WorkspaceProvider.swift` — `WorkspaceProviderStore`, `WorkspaceProviderItem`, `WorkspaceProviderInput` (with `deriveFrom`), `WorkspaceProviderOrigin`, shell execution for list/create/destroy
- `Sources/CmuxConfig.swift` — `workspace_providers` in config, `suspended` field on `CmuxSurfaceDefinition`
- `Sources/ContentView.swift` — `PendingWorkspaceItemView` with spinner/progress/log, `WorkspaceProviderInputSheet` with deriveFrom auto-fill, context menu Stop/Delete/Activate, hidden X button and Close for provider workspaces
- `Sources/Update/UpdateTitlebarAccessory.swift` — `TitlebarNewWorkspaceMenuButton` with NSMenu, hover pre-fetch, NSPanel for inputs, NSAlert for errors, live terminal setup with output file watcher, env injection into layout
- `Sources/TabManager.swift` — `PendingWorkspace` model, suspended workspace selection logic on restore, fresh workspace creation when all suspended
- `Sources/Workspace.swift` — `providerOrigin`, `isSuspended`, `suspendedLayout`, `activateSuspended()`, `suspend()`, suspended command wrapper, session snapshot/restore with provider origin
- `Sources/SessionPersistence.swift` — `SessionProviderOriginSnapshot`, `suspendedLayoutJSON` field
- `Sources/cmuxApp.swift` — shared `WorkspaceProviderStore` with AppDelegate
- `Sources/AppDelegate.swift` — `workspaceProviderStoreForTitlebar` shared store

### Design principles

1. **cmux stays generic.** No knowledge of git, worktrees, or workflows. It just calls commands and gets back workspace definitions.
2. **Live terminal setup.** Users see setup output in real time and can investigate failures interactively.
3. **CLI-based providers.** Any executable can be a provider. Easy to test, language-agnostic.
4. **Suspended workspaces.** Provider workspaces restore as lightweight placeholders. Zero resources until activated.
5. **Clean lifecycle.** Stop/Delete replace ambiguous Close. Destroy only on explicit Delete.

---

## cmux-worktree Provider

Reference provider implementation at `~/workspace/cmux-worktree/`. See its [README](../../cmux-worktree/README.md) for full config documentation.
