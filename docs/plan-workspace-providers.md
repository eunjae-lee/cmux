# Plan: cmux Workspace Provider Extension System

## Overview

Add an extension point to cmux so external tools can inject items into the workspace creation flow. The "+" button (new) in the sidebar becomes a dropdown: "New Workspace" (default) plus items from registered providers. Clicking a provider item runs the provider's setup flow and creates a workspace from its output.

Glowcat becomes a workspace provider — cmux doesn't know about worktrees, pools, or workflows. It just calls the provider and gets back a workspace definition.

## Phase 6 (highest priority): Extension Protocol

### Configuration

In `~/.config/cmux/cmux.json`:

```json
{
  "commands": [ ... ],
  "workspace_providers": [
    {
      "id": "glowcat",
      "name": "Glowcat",
      "list": "glowcat provider list",
      "create": "glowcat provider create"
    }
  ]
}
```

Per-project `.cmux/cmux.json` can also define providers (merged with global).

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique ID for the provider |
| `name` | string | Display name (shown in dropdown header) |
| `list` | string | Shell command that outputs JSON list of items |
| `create` | string | Shell command that sets up and outputs workspace config |

### Protocol

#### `list` command

Called when the user opens the "+" dropdown. Must respond quickly (<2s).

```bash
$ glowcat provider list
```

```json
{
  "items": [
    {
      "id": "my-app",
      "name": "My App",
      "subtitle": "~/workspace/my-app",
      "inputs": [
        {
          "id": "session_name",
          "label": "Session Name",
          "placeholder": "e.g. feature-x",
          "required": true
        }
      ]
    },
    {
      "id": "api-server",
      "name": "API Server",
      "subtitle": "~/workspace/api"
    }
  ]
}
```

`inputs` is optional. If present, cmux shows an input sheet before calling `create`.

Items with no `inputs` create the workspace immediately on click.

#### `create` command

Called with item ID and collected inputs as args. Can take time (setup scripts, worktree creation).

```bash
$ glowcat provider create --id my-app --input session_name=crimson-fox
```

Stdout is newline-delimited. Lines prefixed with `progress:` are shown as status text. The last non-progress line must be JSON — the workspace definition on success, or an error object on failure.

**Success:**
```
progress: Creating worktree...
progress: Running setup (bun install)...
progress: Starting session...
{"title":"My App · crimson-fox","cwd":"/path/to/worktree","layout":{"pane":{"surfaces":[{"type":"terminal","name":"Shell"}]}}}
```

**Failure:**
```
progress: Creating worktree...
progress: Running setup...
{"error":"Setup script failed with exit code 1"}
```

The workspace definition JSON matches cmux's existing `CmuxWorkspaceDefinition` format:

```json
{
  "title": "My App · crimson-fox",
  "cwd": "/Users/eunjae/workspace/my-app/.worktrees/crimson-fox",
  "color": "#3498DB",
  "layout": {
    "direction": "horizontal",
    "children": [
      {
        "pane": {
          "surfaces": [
            { "type": "terminal", "name": "Shell" }
          ]
        }
      },
      {
        "pane": {
          "surfaces": [
            { "type": "terminal", "name": "Dev", "command": "bun run dev" },
            { "type": "browser", "name": "Preview", "url": "http://localhost:3000" }
          ]
        }
      }
    ]
  },
  "env": {
    "GLOWCAT_PORT": "40000",
    "GLOWCAT_INSTANCE_ID": "crimson-fox"
  }
}
```

### UX Flow

```
User clicks "+" in sidebar
  → Dropdown appears:
      ┌──────────────────────┐
      │ New Workspace        │  ← default (Cmd+N behavior)
      │ ──────────────────── │
      │ Glowcat              │  ← provider name (header)
      │   My App             │
      │   API Server         │
      │ ──────────────────── │
      │ Another Provider     │  ← second provider (if any)
      │   ...                │
      └──────────────────────┘
  → User clicks "My App"
  → If item has inputs → input sheet appears
      ┌──────────────────────────┐
      │ My App                   │
      │                          │
      │ Session Name *           │
      │ ┌──────────────────────┐ │
      │ │ e.g. feature-x       │ │
      │ └──────────────────────┘ │
      │                          │
      │        Cancel   Create   │
      └──────────────────────────┘
  → User types name, clicks Create
  → cmux runs: glowcat provider create --id my-app --input session_name=feature-x
  → While running, sidebar shows a placeholder workspace entry with spinner + progress text
  → On success → workspace appears, tabs/splits load, workspace is selected
  → On failure → error alert, placeholder removed
```

### cmux Implementation

**New files:**
- `Sources/WorkspaceProvider.swift` — `WorkspaceProviderStore` (list/create protocol), `WorkspaceProviderItem`, provider process execution

**Modified files:**
- `Sources/CmuxConfig.swift` — Add `workspace_providers` to `CmuxConfigFile`
- `Sources/ContentView.swift` — Add "+" button to sidebar (above workspace list or in footer), wire to dropdown menu with provider items
- `Sources/TabManager.swift` — Add `createWorkspaceFromProvider(definition:)` that takes a `CmuxWorkspaceDefinition` and creates the workspace

**Minimal changes to existing code.** The provider system reuses `CmuxWorkspaceDefinition` and `applyCustomLayout()` for workspace creation — the same code path as cmux.json workspace commands.

### Why This Design

1. **cmux stays generic.** No knowledge of git, worktrees, or glowcat concepts. It just calls a command and gets back a workspace definition.

2. **Reuses existing format.** The create output is a `CmuxWorkspaceDefinition` — same JSON structure used by cmux.json workspace commands. No new layout/config format to invent.

3. **Progressive complexity.** Simple providers just return `{"title":"...","cwd":"..."}`. Complex providers use layouts, inputs, progress streaming.

4. **CLI-based.** Providers are any executable. Easy to test (`glowcat provider list | jq`), easy to debug, language-agnostic.

5. **Fast feedback.** Progress lines stream in real-time. Users see what's happening during long setups.

---

## Env Var Injection

Confirmed: cmux supports env vars at every level.

- `CmuxSurfaceDefinition` has `env: [String: String]?` — per-surface
- `TabManager.addWorkspace(initialTerminalEnvironment:)` — workspace-level
- `workspace.create` socket API accepts `initial_env`
- `applyCustomLayout` passes `surface.env` to each `newTerminalSurface`

The provider's `create` output includes env vars on each surface:
```json
{
  "surfaces": [{
    "type": "terminal",
    "name": "Dev",
    "command": "bun run dev",
    "env": { "GLOWCAT_PORT": "40010", "GLOWCAT_INSTANCE_ID": "crimson-fox" }
  }]
}
```

Additionally, the workspace definition itself should support a top-level `env` that gets applied to all surfaces (convenience for port injection). This may need a small cmux-side addition — currently `CmuxWorkspaceDefinition` doesn't have a top-level `env`, only per-surface. The provider can work around it by putting env on every surface, but a top-level merge would be cleaner.

---

## Phases 1–5: Provider Scripts

Once the extension system exists, the provider is a set of scripts + a YAML config. No separate binary needed.

### Phase 1: "+" Dropdown + Provider Integration

Add a "+" button to the cmux sidebar. Wire it to show "New Workspace" + items from `workspace_providers`. No project-specific code in cmux.

### Phase 2: Simple Non-Worktree Project

Write provider scripts (bash/bun) that read a YAML config:

```yaml
# ~/.config/glowcat/projects.yml
port_base: 40000

projects:
  - id: cmux
    name: cmux
    path: ~/workspace/cmux
    worktree: false
    tabs:
      - name: Shell
      - name: Git
        command: "lazygit"
      - name: Info
        command: "pwd"
```

Provider `list` script → parses YAML → outputs `[{id: "cmux", name: "cmux", subtitle: "~/workspace/cmux"}]`

Provider `create` script → reads project config → outputs workspace definition JSON with surfaces for each tab.

### Phase 3: Suspended Tabs

Research how to handle "suspended" tabs in cmux. Options to investigate:
- cmux's `waitAfterCommand` on `CmuxSurfaceConfigTemplate`
- Starting the terminal but not running the command (show command in prompt?)
- A "press Enter to run" UX

### Phase 4: Worktree Support

Add worktree creation to the `create` script. The provider:
1. Returns `inputs: [{id: "session_name", ...}]` in the list response
2. On create: `git worktree add` → runs setup → outputs workspace def with worktree cwd

Progress streaming handles the delayed creation:
```
progress: Creating worktree...
progress: Running setup...
{"title":"cmux · feature-x","cwd":"/path/to/worktree",...}
```

Setup failure returns `{"error":"..."}` and cmux shows an error alert.

**State management:** The create script manages a state file (`~/.config/glowcat/state.json`) tracking:
- Active instances (id, project, port, worktree path, branch)
- Port allocations (scanned against workspace directory on each run — freed if worktree is gone)

**Workspace directory:** `~/.config/glowcat/workspaces/<project-id>/<instance-name>/`

**Port allocation:** On create, the script reads state, finds the next free port block (starting from `port_base`, skipping allocated ports), writes it to state, and includes `GLOWCAT_PORT` in the surface env vars.

### Phase 5: Workflows (backlog)

Add workflow support. Workflows would be additional items in the list response with `inputs`. Deferred for now.
