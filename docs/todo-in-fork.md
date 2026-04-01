# TODO: Fork Roadmap

## Remote provider workspaces

Run provider workflows on remote machines over SSH.

**Concept:** The remote machine has its own `cmux-worktree` binary and `~/.config/cmux-worktree/projects.yml`. cmux reads the remote provider list and runs create/destroy on the remote side. The existing `cmux ssh` handles connection, daemon, and browser proxying.

**Flow:**
1. SSH into the remote machine
2. Read remote provider config: `ssh user@host cmux-worktree list`
3. Show remote items in the "+" menu (marked as remote)
4. Run create on remote: `ssh user@host cmux-worktree create --id ...`
5. Setup runs in a remote terminal (user watches live)
6. Layout applied with remote terminals + proxied browser

**Key insight:** The provider protocol is CLI-based, so it works over SSH without protocol changes — just a transport layer.

**Prerequisites:**
- `cmux-worktree` installed on the remote machine
- Remote machine has its own projects.yml config
- Existing `cmux ssh` infrastructure handles the rest

## Setup in terminal improvements

Currently setup runs in a terminal and on success the layout replaces it. Possible improvements:

- Keep a "Setup Log" tab after layout is applied (instead of closing it)
- Add a "Retry Setup" option if setup fails
- Stream setup output via pty instead of captured process (for interactive installers)

## Suspended workspace UX

- Show a welcome/empty state when a suspended workspace is selected (instead of creating a blank workspace when all are suspended)
- Add a visual indicator (icon/badge) on suspended items beyond opacity
- Add keyboard shortcut to activate/suspend workspaces

## Browser isolation

- Per-workspace browser profile selection (not just isolated storage)
- Option to inherit cookies from a specific profile into an isolated workspace

## Localization

- All new user-facing strings use `String(localized:defaultValue:)` but Japanese translations are missing
- Strings to translate: context menu items (Stop, Activate, Delete Workspace), input sheet labels, pending workspace status text, confirmation dialogs

## Pre-push build optimization

- Currently builds on every push, even for doc-only changes
- Could skip build if only `.md`, `.yml`, or non-Swift files changed
- Could cache build artifacts and skip if no Swift source changed since last build

## Provider protocol extensions

- **`update` command** — re-run setup on an existing workspace without destroying it (e.g. after pulling new deps)
- **`status` command** — provider reports workspace health (e.g. worktree dirty, outdated deps) shown as badge/indicator in sidebar
- **Provider-defined context menu items** — providers can add custom actions beyond Stop/Delete (e.g. "Pull & Rebuild", "Open in GitHub")
- **Multiple layout variants per workflow** — e.g. "Dev Session" could offer "minimal" (shell only) vs "full" (shell + server + browser)

## cmux-worktree improvements

- **List active worktrees** — show existing worktrees in the "+" menu so you can reopen a closed workspace without recreating
- **Worktree cleanup tool** — command to list and prune orphaned worktrees in `~/.cmux/workspaces/`
- **Auto-detect projects** — scan `~/workspace/` for git repos instead of manual config
- **Per-workflow tabs/layout override** — different workflows could have different tab layouts (e.g. "Review" doesn't need a dev server tab)

## Testing

- E2E test for provider create → layout applied flow
- E2E test for suspended workspace restore → activate
- E2E test for destroy on delete
