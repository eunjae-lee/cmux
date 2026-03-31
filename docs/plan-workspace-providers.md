# Plan: cmux Workspace Provider Extension System

## Current Status

| Phase | Status | Notes |
|-------|--------|-------|
| Phase 6: Extension Protocol (cmux side) | ✅ Done | |
| Phase 1: "+" Dropdown + Provider Integration | ✅ Done | Titlebar "+" button with NSMenu |
| Phase 2: Simple Non-Worktree Project | ✅ Done | cmux-worktree provider |
| Phase 3: Suspended Tabs | ✅ Done | `suspended: true` on surfaces |
| Phase 4: Worktree Support | ✅ Done | git worktree create/destroy |
| Phase 5: Workflows | ✅ Done | Per-project workflows with branch_from |

### Future work

- **Setup in terminal** — run setup scripts in a live terminal instead of background process, so users can investigate failures interactively

---

## Overview

An extension point in cmux so external tools can inject items into the workspace creation flow. The "+" button in the titlebar shows a dropdown: "New Workspace" (default) plus items from registered providers. Clicking a provider item runs the provider's setup flow and creates a workspace from its output.

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
      "list": "/path/to/bun run /path/to/cmux-worktree/src/cli.ts list",
      "create": "/path/to/bun run /path/to/cmux-worktree/src/cli.ts create",
      "destroy": "/path/to/bun run /path/to/cmux-worktree/src/cli.ts destroy"
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
| `create` | string | Shell command that sets up and outputs workspace config |
| `destroy` | string? | Shell command called when a provider-created workspace is closed |

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

Called with item ID and collected inputs as args.

```bash
provider create --id my-project::blank --input session=feature-x --input branch=feature-x
```

Stdout is newline-delimited. Lines prefixed with `progress:` update the pending workspace placeholder in the sidebar. The last non-progress line must be JSON.

**Success:**
```
progress: Creating worktree "feature-x"...
progress: Running base setup...
progress: Installing dependencies...
progress: Done!
progress: Running workflow setup...
{"title":"feature-x · My Project","cwd":"/path/to/worktree","env":{...},"layout":{...}}
```

**Failure:**
```
progress: Creating worktree...
{"error":"Setup script failed with exit code 1"}
```

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
    "pane": {
      "surfaces": [
        { "type": "terminal", "name": "Shell" },
        { "type": "terminal", "name": "Git", "command": "lazygit", "suspended": true },
        { "type": "browser", "name": "Preview", "url": "http://localhost:3000" }
      ]
    }
  }
}
```

#### `destroy` command

Called when a provider-created workspace is closed. Runs async in background.

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

### Suspended mode

When `suspended: true` and `command` is set, the terminal shows:

```
▶ Press Enter to run: lazygit
```

The screen is cleared first. Pressing Enter runs the command. When the command exits (Ctrl-C, crash, or normal quit), the prompt returns. Press Enter to re-run.

## UX Flow

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
  → Pending workspace appears in sidebar with spinner + progress
  → ⓘ button opens log panel showing all progress lines
  → On success → real workspace replaces pending, tabs/splits load
  → On failure → pending shows error with ⚠️ icon and ✕ dismiss

User closes workspace
  → cmux calls destroy command in background
  → Provider cleans up (removes worktree, etc.)
```

## cmux Implementation

### Files modified

- `Sources/WorkspaceProvider.swift` — `WorkspaceProviderStore`, `WorkspaceProviderItem`, `WorkspaceProviderInput` (with `deriveFrom`), `WorkspaceProviderOrigin`, shell execution for list/create/destroy
- `Sources/CmuxConfig.swift` — `workspace_providers` in config, `suspended` field on `CmuxSurfaceDefinition`
- `Sources/ContentView.swift` — `PendingWorkspaceItemView` with spinner/progress/log, `WorkspaceProviderInputSheet` with deriveFrom auto-fill
- `Sources/Update/UpdateTitlebarAccessory.swift` — `TitlebarNewWorkspaceMenuButton` with NSMenu, hover pre-fetch, NSPanel for inputs, NSAlert for errors
- `Sources/TabManager.swift` — `PendingWorkspace` model with progress log, destroy hook in `closeWorkspace`
- `Sources/Workspace.swift` — `providerOrigin` property, suspended command wrapper in `applyCustomLayout`
- `Sources/cmuxApp.swift` — shared `WorkspaceProviderStore` with AppDelegate
- `Sources/AppDelegate.swift` — `workspaceProviderStoreForTitlebar` shared store

### Design principles

1. **cmux stays generic.** No knowledge of git, worktrees, or workflows. It just calls commands and gets back workspace definitions.
2. **Reuses existing format.** Create output is a `CmuxWorkspaceDefinition` — same JSON structure used by cmux.json workspace commands.
3. **CLI-based providers.** Any executable can be a provider. Easy to test (`provider list | jq`), language-agnostic.
4. **Progressive complexity.** Simple providers just return `{"title":"...","cwd":"..."}`. Complex providers use layouts, inputs, workflows, progress streaming.

---

## cmux-worktree Provider

Reference provider implementation at `~/workspace/cmux-worktree/`.

### Config

`~/.config/cmux-worktree/projects.yml`:

```yaml
projects:
  - id: cmux
    name: cmux
    path: ~/workspace/cmux
    worktree: true
    setup: bun install
    workflows:
      - name: Blank
      - name: From PR
        branch_from: pr_url
        inputs:
          - id: pr_url
            label: PR URL
            required: true
        setup: echo "Setting up PR review..."
      - name: Dev Session
        setup: echo "Starting dev environment..."
    tabs:
      - name: Shell
      - name: Git
        command: lazygit
        suspended: true

  - id: simple
    name: Simple Project
    path: ~/workspace/simple
    tabs:
      - name: Shell
```

### Features

- **Simple projects** — open a workspace at a directory with configured tabs
- **Worktree projects** — create git worktrees in `~/.cmux/workspaces/<project>/<branch>/`
- **Workflows** — per-project workflows with different setup steps and input types
  - `branch_from: session` (default) — slugify session name into branch
  - `branch_from: pr_url` — extract branch from GitHub PR URL via `gh` CLI
- **Base + workflow setup** — base setup always runs, workflow setup runs on top
- **Suspended tabs** — commands show "Press Enter to run" prompt, re-run on exit
- **Cleanup on close** — destroy command removes git worktree when workspace is closed
- **Env vars** — `CMUX_PROVIDER_PROJECT`, `CMUX_PROVIDER_WORKFLOW`, `CMUX_PROVIDER_SESSION`, `CMUX_PROVIDER_BRANCH`, `CMUX_PROVIDER_INPUT_*`
