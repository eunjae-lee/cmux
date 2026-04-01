# Changes in Fork: Workspace Provider Extension System

Branch: `feat/workspace-providers` (based on `main`)

## Summary

Adds an extension point so external tools can register as workspace providers. The "+" button in the titlebar shows provider items alongside "New Workspace". Providers handle project-specific logic (git worktrees, setup scripts, workflows) while cmux stays generic.

## File Structure

### New files (no merge conflicts)

| File | Lines | Purpose |
|------|-------|---------|
| `Sources/WorkspaceProvider.swift` | 353 | Provider protocol models, store, shell execution |
| `Sources/WorkspaceProviderTitlebarButton.swift` | 441 | Titlebar "+" menu, input panel, file watcher, layout application |
| `Sources/WorkspaceProviderViews.swift` | 249 | Input sheet with deriveFrom, pending workspace item, log viewer |
| `cmuxTests/WorkspaceProviderTests.swift` | 296 | Unit tests for parsing, escaping, persistence |
| `docs/plan-workspace-providers.md` | 282 | Full design doc |
| `docs/changes-in-fork.md` | — | This file |
| `docs/macos-26-zig-workaround.md` | 90 | Zig + macOS 26 build workaround |
| `scripts/dev.sh` | 11 | Quick dev build shortcut |

### Modified upstream files (minimal changes)

#### `Sources/Update/UpdateTitlebarAccessory.swift` (+29 lines)

- `TitlebarControlsView` — added `workspaceProviderStore` parameter
- `TitlebarControlsAccessoryViewController` — passes provider store through init
- `UpdateTitlebarAccessoryController` — stores and passes `workspaceProviderStore`
- `HiddenTitlebarSidebarControlsView` — reads provider store from environment
- Titlebar "+" button replaced with `TitlebarNewWorkspaceMenuButton` (defined in new file)

#### `Sources/ContentView.swift` (+110 lines)

- `ContentView` — added `@EnvironmentObject var workspaceProviderStore`
- `fullscreenControls` — passes `workspaceProviderStore` to `TitlebarControlsView`
- `VerticalTabsSidebar` ForEach — added `PendingWorkspaceItemView` after workspace list, `.opacity(0.4)` for suspended workspaces, hidden X button for provider workspaces
- `workspaceContextMenu` — added provider section: Stop/Activate/Delete Workspace with confirmation dialog
- Hidden Close Workspace / Close Others / Close Above / Close Below for provider workspaces

#### `Sources/Workspace.swift` (+122 lines)

- Properties: `providerOrigin`, `isSuspended`, `suspendedLayout`
- `sendCommandToFirstTerminal()` — public API for sending command to first terminal
- `activateSuspended()` / `suspend()` — lifecycle methods
- `suspendedCommandWrapper()` — generates "Press Enter to run" shell loop
- `configureExistingSurface` / `createNewSurface` — suspended command support
- `sessionSnapshot()` — serializes provider origin + suspended layout
- `restoreSessionSnapshot()` — restores as suspended for provider workspaces

#### `Sources/TabManager.swift` (+61 lines)

- `PendingWorkspace` class — model with progress, log lines, state, provider origin
- `pendingWorkspaces` published array
- `selectWorkspace` — activates suspended workspaces on selection
- Session restore — skips suspended for initial selection, creates fresh workspace if all suspended

#### `Sources/SessionPersistence.swift` (+12 lines)

- `SessionProviderOriginSnapshot` struct
- `SessionWorkspaceSnapshot` — added `providerOrigin` and `suspendedLayoutJSON` optional fields

#### `Sources/CmuxConfig.swift` (+28 lines)

- `CmuxSurfaceDefinition` — added `suspended: Bool?`
- `CmuxConfigFile` — added `workspace_providers`
- `CmuxConfigStore` — added `onProvidersChanged` callback

#### `Sources/cmuxApp.swift` (+8 lines)

- `workspaceProviderStore` computed property from AppDelegate's shared store
- `.environmentObject(workspaceProviderStore)` in WindowGroup
- `onProvidersChanged` wiring

#### `Sources/AppDelegate.swift` (+8 lines)

- `workspaceProviderStoreForTitlebar` shared instance
- Window creation reuses shared store

#### `GhosttyTabs.xcodeproj/project.pbxproj` (+12 lines)

- File references for `WorkspaceProvider.swift`, `WorkspaceProviderTitlebarButton.swift`, `WorkspaceProviderViews.swift`

## How to replay

### 1. Add new files

Copy these files as-is — they have no dependencies on fork-specific changes:
- `Sources/WorkspaceProvider.swift`
- `Sources/WorkspaceProviderTitlebarButton.swift`
- `Sources/WorkspaceProviderViews.swift`
- `cmuxTests/WorkspaceProviderTests.swift`
- `scripts/dev.sh`
- `docs/plan-workspace-providers.md`

Add them to the Xcode project.

### 2. Apply minimal upstream changes

Each upstream file needs a small, localized change:

**CmuxConfig.swift:**
- Add `suspended: Bool?` to `CmuxSurfaceDefinition`
- Add `workspace_providers: [WorkspaceProviderDefinition]?` to `CmuxConfigFile`
- Add `onProvidersChanged` callback to `CmuxConfigStore`, fire it in `loadAll()`

**SessionPersistence.swift:**
- Add `SessionProviderOriginSnapshot` struct
- Add two optional fields to `SessionWorkspaceSnapshot`

**AppDelegate.swift:**
- Add `workspaceProviderStoreForTitlebar = WorkspaceProviderStore()` property
- Pass it to `UpdateTitlebarAccessoryController` init
- Reuse it in window creation instead of creating a new store

**cmuxApp.swift:**
- Add computed `workspaceProviderStore` from AppDelegate
- Inject as environment object
- Wire `onProvidersChanged`

**UpdateTitlebarAccessory.swift:**
- Add `workspaceProviderStore` parameter to `TitlebarControlsView`
- Thread it through `TitlebarControlsAccessoryViewController` and `HiddenTitlebarSidebarControlsView`
- Replace "+" button with `TitlebarNewWorkspaceMenuButton`

**TabManager.swift:**
- Add `PendingWorkspace` class and `pendingWorkspaces` array
- Add suspended activation in `selectWorkspace`
- Add suspended-aware selection in session restore

**Workspace.swift:**
- Add `providerOrigin`, `isSuspended`, `suspendedLayout` properties
- Add `sendCommandToFirstTerminal`, `activateSuspended`, `suspend` methods
- Add `suspendedCommandWrapper` for suspended command support
- Modify `configureExistingSurface` / `createNewSurface` for suspended commands
- Add provider origin to session snapshot/restore

**ContentView.swift:**
- Add `workspaceProviderStore` environment object to `ContentView`
- Add pending workspace rendering in sidebar ForEach
- Add `.opacity(0.4)` for suspended workspaces
- Hide X button for provider workspaces
- Add provider context menu section (Stop/Activate/Delete)
- Hide Close Workspace options for provider workspaces

### Key architectural decisions

1. **Provider protocol** — CLI-based: `list` (JSON stdout), `create` (runs in terminal, writes to `$CMUX_PROVIDER_OUTPUT`), `destroy` (background cleanup)
2. **Titlebar integration** — NSMenu + NSPanel (not SwiftUI Menu/sheet) because AppKit titlebar accessory
3. **Shared store** — `WorkspaceProviderStore` shared between AppDelegate and cmuxApp via stored property
4. **Suspended workspaces** — provider workspaces restore without terminals, activated on click
5. **Suspended commands** — shell `while` loop: clear → prompt → read → execute → repeat
6. **deriveFrom** — input field auto-fill by slugifying another field's value
7. **Env injection** — workspace-level env merged recursively into every layout surface
8. **File watcher** — `DispatchSource` monitors temp directory for provider output file
9. **Lifecycle** — Stop (suspend), Delete (destroy + close), no regular Close for provider workspaces
10. **Browser isolation** — `isolate_browser: true` on provider gives each workspace its own `WKWebsiteDataStore`, reusing the remote workspace pattern
