---
name: merge-upstream
description: Fetch latest upstream (origin/main) and merge into the fork, then push to eunjae-lee remote
allowed-tools: Bash(git *), Read, Edit
---

# Merge Upstream into Fork

Fetch the latest changes from upstream `manaflow-ai/cmux` and merge them into the local `main` branch, then push to the `eunjae-lee` fork.

## 1. Ensure we're on main

```bash
git checkout main
```

## 2. Fetch upstream

```bash
git fetch origin main
```

## 3. Show what's incoming

```bash
git log --oneline HEAD..origin/main
```

If nothing new, inform the user and stop.

## 4. Merge

```bash
git merge origin/main --no-edit
```

If the merge completes cleanly, go to step 6.

## 5. Resolve conflicts

If there are conflicts:

1. Run `git status` to see conflicted files.
2. For each conflicted file, read it and understand both sides.
3. **Our provider code lives in separate files** — conflicts are most likely in:
   - `Sources/ContentView.swift` (sidebar ForEach, context menu)
   - `Sources/Workspace.swift` (properties, session restore)
   - `Sources/TabManager.swift` (selectWorkspace, session restore)
   - `Sources/Update/UpdateTitlebarAccessory.swift` (titlebar controls)
   - `Sources/cmuxApp.swift` (environment objects)
   - `Sources/AppDelegate.swift` (shared stores)
   - `GhosttyTabs.xcodeproj/project.pbxproj` (file references)
4. Resolve by keeping upstream changes and re-applying our small additions. Refer to `docs/changes-in-fork.md` for what our changes are in each file.
5. `git add <file>` each resolved file.

## 6. Verify build

```bash
./scripts/dev.sh
```

If the build fails, fix compilation errors and amend the merge commit.

## 7. Push to fork

```bash
git push eunjae-lee main
```

## Notes

- `origin` = upstream (`manaflow-ai/cmux`)
- `eunjae-lee` = fork (`eunjae-lee/cmux`)
- Never force-push to either remote without asking
- If conflicts are complex, show the user and ask before resolving
- After merging, check `docs/changes-in-fork.md` to ensure our additions are still intact
