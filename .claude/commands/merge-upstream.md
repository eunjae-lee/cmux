# Merge Upstream into Fork

Fetch the latest changes from upstream `manaflow-ai/cmux` and merge them into the local `main` branch, then push to the fork.

## 1. Ensure we're on main

```bash
git checkout main
```

## 2. Fetch upstream

```bash
git fetch upstream main
```

## 3. Show what's incoming

```bash
git log --oneline HEAD..upstream/main
```

If nothing new, inform the user and stop.

## 4. Merge

```bash
git merge upstream/main --no-edit
```

If the merge completes cleanly, go to step 6.

## 5. Resolve conflicts

### Submodule conflicts (ghostty, vendor/bonsplit)

These conflict on almost every upstream merge. Resolution:

```bash
# For each conflicted submodule, take upstream's version:
UPSTREAM_SHA=$(git ls-tree upstream/main <submodule> | awk '{print $3}')
cd <submodule> && git fetch origin && git checkout $UPSTREAM_SHA && cd ..
git add <submodule>
```

### Download updated GhosttyKit xcframework

After updating the ghostty submodule, download the pre-built xcframework (zig can't build on macOS 26):

```bash
# Clean ghostty submodule first (stale files cause dirty cache key)
cd ghostty && git clean -fdx && cd ..

GHOSTTY_SHA=$(git -C ghostty rev-parse HEAD)
CACHE_DIR="$HOME/.cache/cmux/ghosttykit/$GHOSTTY_SHA"
if [ ! -d "$CACHE_DIR/GhosttyKit.xcframework" ]; then
  mkdir -p /tmp/ghosttykit-download "$CACHE_DIR"
  gh release download "xcframework-$GHOSTTY_SHA" --repo manaflow-ai/ghostty --pattern "GhosttyKit.xcframework.tar.gz" --dir /tmp/ghosttykit-download
  tar xzf /tmp/ghosttykit-download/GhosttyKit.xcframework.tar.gz -C /tmp/ghosttykit-download
  mv /tmp/ghosttykit-download/GhosttyKit.xcframework "$CACHE_DIR/"
  rm -rf /tmp/ghosttykit-download
fi
ln -sfn "$CACHE_DIR/GhosttyKit.xcframework" GhosttyKit.xcframework
```

### Source code conflicts

Our provider code lives in separate files so conflicts are rare. When they occur:

1. Run `git status` to see conflicted files.
2. For each file, read the conflict markers.
3. Refer to `docs/changes-in-fork.md` for what our changes are.
4. **Key principle:** keep upstream changes, re-apply our small additions.
5. Common conflicts:
   - `Sources/ContentView.swift` — our changes use `tab.isProviderWorkspace` (a computed property). Just keep upstream's line and append `&& !tab.isProviderWorkspace` where needed.
   - `Sources/cmuxApp.swift` — our `workspaceProviderStore` is after `primaryWindowId`, away from `@StateObject` block. If upstream adds properties near there, just keep both.
   - `GhosttyTabs.xcodeproj/project.pbxproj` — keep upstream changes, ensure our file references still exist.
6. `git add <file>` each resolved file.

### Complete the merge

```bash
git commit --no-edit
```

## 6. Verify build

```bash
./scripts/dev.sh
```

If the build fails:
- **zig errors:** clean ghostty submodule (`cd ghostty && git clean -fdx`) and re-download xcframework
- **SPM errors:** `rm -rf /tmp/cmux-release` and retry
- **Swift compilation errors:** fix and amend the merge commit

## 7. Push to fork

```bash
git push origin main
```

## Notes

- `upstream` = upstream repo (`manaflow-ai/cmux`)
- `origin` = fork (`eunjae-lee/cmux`)
- Never force-push to either remote without asking
- If conflicts are complex, show the user and ask before resolving
- After merging, check `docs/changes-in-fork.md` to ensure our additions are still intact
- The push triggers the pre-push hook (release build + homebrew tap update)
