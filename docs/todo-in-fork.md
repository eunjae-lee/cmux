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
