# Changes in Fork: Workspace Provider Extension System

Branch: `feat/workspace-providers` (based on `main`)

## Summary

Adds an extension point so external tools can register as workspace providers. The "+" button in the titlebar shows provider items alongside "New Workspace". Providers handle project-specific logic (git worktrees, setup scripts, workflows) while cmux stays generic.

## Files Changed

### New files

#### `Sources/WorkspaceProvider.swift` (+348 lines)
- `WorkspaceProviderDefinition` — provider config model (`id`, `name`, `list`, `create`, `destroy`)
- `WorkspaceProviderItem` — list response model with optional `inputs`
- `WorkspaceProviderInput` — input field model with `deriveFrom` for auto-fill
- `WorkspaceProviderCreateResult` — create response model (title, cwd, color, env, layout)
- `WorkspaceProviderOrigin` — metadata stored on workspaces for destroy on delete
- `WorkspaceProviderStore` — `ObservableObject` managing providers, cached items, list/create execution
- `WorkspaceProviderExecutor` — shell execution for list, create, destroy commands
  - `runList` — runs list command, parses JSON response
  - `runCreate` — runs create command with streaming, parses output file
  - `runDestroy` — runs destroy command in background
  - `runShellCommand` / `runShellCommandStreaming` — shell process helpers

#### `scripts/dev.sh` (+11 lines)
- Quick shortcut: `./scripts/dev.sh [tag]` → `./scripts/reload.sh --tag <tag> --launch`

#### `docs/plan-workspace-providers.md` (+282 lines)
- Full design doc covering protocol, UX flow, implementation details

#### `docs/macos-26-zig-workaround.md` (+90 lines)
- Documents Zig 0.15.2 + macOS 26 linker incompatibility and CI xcframework workaround

### Modified files

#### `Sources/Update/UpdateTitlebarAccessory.swift` (+423/-18 lines)
- `TitlebarNewWorkspaceMenuButton` — replaces the simple "+" button with a menu button
  - Shows NSMenu with "New Workspace" + provider items grouped by provider name
  - Hover pre-fetches items with 10s TTL (`prefetchIfStale`, `fetchThenShowMenu`)
  - `MenuAnchorView` (NSViewRepresentable) positions menu below the button
  - `showInputPanel` — NSPanel-based input dialog (SwiftUI `.sheet` doesn't work from AppKit titlebar)
  - `showErrorAlert` — NSAlert for errors (same reason)
  - `startCreate` — creates workspace with setup terminal, sets `CMUX_PROVIDER_OUTPUT` env var, sends create command to terminal
  - `watchForProviderOutput` — polls for output file (1s interval, 30min timeout)
  - `applyProviderResult` — reads output file, sets provider origin, applies layout with env injection
  - `injectEnvIntoLayout` — recursively merges workspace-level env into every surface
- `TitlebarControlsView` — added `workspaceProviderStore` parameter
- `TitlebarControlsAccessoryViewController` — passes provider store through init
- `UpdateTitlebarAccessoryController` — stores and passes `workspaceProviderStore`
- `HiddenTitlebarSidebarControlsView` — reads provider store from environment
- `TitlebarMenuTarget` — NSObject target for NSMenu actions

#### `Sources/ContentView.swift` (+347/-24 lines)
- `ContentView` — added `@EnvironmentObject var workspaceProviderStore`
- `VerticalTabsSidebar` — renders `PendingWorkspaceItemView` after workspace list; adds `.opacity(0.4)` for suspended workspaces; hides X button for provider workspaces (`canCloseWorkspace && tab.providerOrigin == nil`)
- `fullscreenControls` — passes `workspaceProviderStore` to `TitlebarControlsView`
- `workspaceContextMenu` — added provider-specific section:
  - **Stop** (active → suspend) / **Activate** (suspended → active)
  - **Delete Workspace** with NSAlert confirmation dialog → calls destroy → closes
  - Hides Close Workspace / Close Others / Close Above / Close Below for provider workspaces
- `PendingWorkspaceItemView` — sidebar item with spinner + progress text during creation, error state with ⚠️ + dismiss, ⓘ log button
- `PendingWorkspaceLogButton` / `PendingWorkspaceLogView` — floating NSPanel with scrollable monospace log, auto-scrolls, shows error at bottom
- `WorkspaceProviderInputSheet` — input form with `deriveFrom` support (auto-slugify), internal `@State` for reactive derived fields, `bindingForInput` helper to avoid complex expressions
- `SidebarFooterButtons` — removed `workspaceProviderStore` dependency (moved to titlebar)

#### `Sources/Workspace.swift` (+116/-2 lines)
- Added properties: `providerOrigin: WorkspaceProviderOrigin?`, `isSuspended: Bool`, `suspendedLayout: CmuxLayoutNode?`
- `activateSuspended()` — creates terminals from saved layout
- `suspend()` — tears down all panels, sets `isSuspended = true`
- `suspendedCommandWrapper(_:)` — generates `while true; do clear; printf '▶ Press Enter to run:...'; read; <cmd>; done`
- `sendInputWhenReady` — changed from `private` to `internal` for titlebar create flow
- `configureExistingSurface` / `createNewSurface` — uses `suspendedCommandWrapper` when `surface.suspended == true`
- `sessionSnapshot` — serializes `providerOrigin` and `suspendedLayout` (JSON-encoded `CmuxLayoutNode`)
- `restoreSessionSnapshot` — restores `providerOrigin`; provider workspaces skip terminal restoration and set `isSuspended = true`

#### `Sources/TabManager.swift` (+61/-2 lines)
- `PendingWorkspace` class — `ObservableObject` with `title`, `progress`, `logLines`, `state` (.loading/.failed), `providerOrigin`, `appendProgress()`
- `pendingWorkspaces: [PendingWorkspace]` published array
- `selectWorkspace` — calls `activateSuspended()` when selecting a suspended workspace
- `closeWorkspace` — removed auto-destroy (destroy only on explicit Delete)
- Session restore selection — skips suspended workspaces; creates fresh default workspace if all are suspended

#### `Sources/SessionPersistence.swift` (+12 lines)
- `SessionProviderOriginSnapshot` — Codable struct for persisting provider origin
- `SessionWorkspaceSnapshot` — added optional `providerOrigin` and `suspendedLayoutJSON` fields

#### `Sources/CmuxConfig.swift` (+28 lines)
- `CmuxSurfaceDefinition` — added `suspended: Bool?` field
- `CmuxConfigFile` — added `workspace_providers: [WorkspaceProviderDefinition]?`
- `CmuxConfigStore` — added `onProvidersChanged` callback, fires on config load

#### `Sources/AppDelegate.swift` (+8/-1 lines)
- `workspaceProviderStoreForTitlebar` — shared `WorkspaceProviderStore` instance used by both titlebar (AppKit) and SwiftUI
- Window creation reuses the shared store instead of creating a new one

#### `Sources/cmuxApp.swift` (+8 lines)
- `workspaceProviderStore` computed property returning `appDelegate.workspaceProviderStoreForTitlebar`
- `.environmentObject(workspaceProviderStore)` injected into WindowGroup
- `cmuxConfigStore.onProvidersChanged` wired to update the shared store

#### `GhosttyTabs.xcodeproj/project.pbxproj` (+4 lines)
- Added `WorkspaceProvider.swift` file reference

## How to replay

1. Apply all changes from the diff: `git diff main...feat/workspace-providers`
2. The key architectural decisions:
   - Provider protocol is CLI-based: `list` (JSON to stdout), `create` (runs in terminal, writes JSON to `$CMUX_PROVIDER_OUTPUT`), `destroy` (background cleanup)
   - Titlebar "+" uses NSMenu (not SwiftUI Menu) because it's in an AppKit titlebar accessory
   - Input dialogs use NSPanel (not SwiftUI `.sheet`) for the same reason
   - `WorkspaceProviderStore` is shared between AppDelegate and cmuxApp via a stored property on AppDelegate
   - Provider workspaces restore as suspended (no terminals) to avoid resource waste on app launch
   - `suspended` command wrapper is a shell `while` loop that clears screen and waits for Enter
   - `deriveFrom` on input fields enables auto-slugify (e.g. session name → branch name)
   - Workspace-level env vars are injected into every surface by `injectEnvIntoLayout`
