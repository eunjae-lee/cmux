# Building on macOS 26 (Tahoe)

## Problem

Zig 0.15.2's built-in linker (LLD) does not support macOS 26. When running `./scripts/setup.sh`, the GhosttyKit build fails with undefined symbol errors for basic C library functions:

```
error: undefined symbol: _abort
error: undefined symbol: _free
error: undefined symbol: _malloc_size
...
```

This happens because Zig's internal LLD cannot handle `platform_version macos 26.x` — Apple jumped the macOS version from 15 to 26, and LLD in Zig 0.15.2 predates this change.

Zig 0.16.0-dev has the fix, but Ghostty enforces an exact Zig 0.15.2 version requirement.

## Workaround

CI builds and uploads `GhosttyKit.xcframework` as a release on the `manaflow-ai/ghostty` fork. You can download the pre-built framework instead of building it locally.

### Steps

1. **Get the Ghostty submodule SHA:**

   ```bash
   GHOSTTY_SHA=$(git -C ghostty rev-parse HEAD)
   ```

2. **Download the pre-built xcframework:**

   ```bash
   mkdir -p /tmp/ghosttykit-download
   gh release download "xcframework-$GHOSTTY_SHA" \
     --repo manaflow-ai/ghostty \
     --pattern "GhosttyKit.xcframework.tar.gz" \
     --dir /tmp/ghosttykit-download
   ```

3. **Extract and install:**

   ```bash
   cd /tmp/ghosttykit-download
   tar xzf GhosttyKit.xcframework.tar.gz

   CACHE_DIR="$HOME/.cache/cmux/ghosttykit/$GHOSTTY_SHA"
   mkdir -p "$CACHE_DIR"
   mv GhosttyKit.xcframework "$CACHE_DIR/GhosttyKit.xcframework"
   ```

4. **Create the project symlink:**

   ```bash
   cd /path/to/cmux
   ln -sfn "$CACHE_DIR/GhosttyKit.xcframework" GhosttyKit.xcframework
   ```

5. **Build and run:**

   ```bash
   ./scripts/reload.sh --tag first-run
   ```

### One-liner

From the cmux project root:

```bash
GHOSTTY_SHA=$(git -C ghostty rev-parse HEAD) && \
CACHE_DIR="$HOME/.cache/cmux/ghosttykit/$GHOSTTY_SHA" && \
mkdir -p /tmp/ghosttykit-download && \
gh release download "xcframework-$GHOSTTY_SHA" \
  --repo manaflow-ai/ghostty \
  --pattern "GhosttyKit.xcframework.tar.gz" \
  --dir /tmp/ghosttykit-download && \
tar xzf /tmp/ghosttykit-download/GhosttyKit.xcframework.tar.gz -C /tmp/ghosttykit-download && \
mkdir -p "$CACHE_DIR" && \
mv /tmp/ghosttykit-download/GhosttyKit.xcframework "$CACHE_DIR/" && \
ln -sfn "$CACHE_DIR/GhosttyKit.xcframework" GhosttyKit.xcframework && \
rm -rf /tmp/ghosttykit-download && \
echo "✅ GhosttyKit installed from CI"
```

## When this is resolved

This workaround is needed until one of the following:

- Zig releases a 0.15.x patch with macOS 26 linker support
- Ghostty updates its minimum Zig version to 0.16+
- `setup.sh` is updated to automatically download pre-built xcframeworks on macOS 26
