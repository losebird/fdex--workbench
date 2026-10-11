# Build guide — FDE-X Workbench installers

## Why workbench is not in git

Staging a runnable tree is **~2 GB** (`node_modules` + natives). Committing it blows GitHub limits and breaks cross-OS natives.

**Strategy:** ship a **source tarball** (~150 MB uncompressed) as a Release asset; CI installs and builds on each OS.

## Publish `workbench-src` asset (once / when source changes)

On the builder box (with a built FDEDeliveryWorkbench tree):

```bash
bash scripts/pack-workbench-src.sh
# uploads to release tag workbench-src-v0.1.0 by default when GH_TOKEN is set
```

Or manually:

```bash
# produces /tmp/workbench-src.tar.zst — NO node_modules, NO .runtime (no lab seed / credentials)
gh release create workbench-src-v0.1.0 /tmp/workbench-src.tar.zst \
  -R losebird/fdex--workbench \
  --title "Workbench source v0.1.0" \
  --notes "Source only. Prefer private repo. See NOTICE.md."
```

Optional private lab seed (separate asset, **private repo recommended**):

```bash
# not produced by default
```

## CI pipeline

1. `scripts/ci-fetch-workbench.sh` — download release asset
2. `scripts/ci-build-workbench.sh` — `pnpm install` + `pnpm build` (Node 24)
3. `scripts/stage-workbench.sh` + `fetch-node.sh`
4. `electron-builder` → `.dmg` / `.msi` / NSIS `.exe`

## Environment

| Var | Meaning |
|-----|---------|
| `FDEX_SRC_REPO` | Path to FDEDeliveryWorkbench root (default `./workbench-src`) |
| `FDEX_VENDOR` | Vendor path (default `./vendor`) |
| `WORKBENCH_ASSET_URL` | Direct URL override for source tarball |
| `WORKBENCH_ASSET_TAG` | Release tag (default `workbench-src-v0.1.0`) |
| `WORKBENCH_ASSET_NAME` | Asset filename (default `workbench-src.tar.zst`) |
| `FDEX_INCLUDE_RUNTIME_SEED` | `1` to copy `.runtime` seed (off by default) |
| `NODE_VER` | Bundled Node version (default `24.10.0`) |

## Local Linux smoke (optional)

```bash
export FDEX_SRC_REPO=/path/to/FDEDeliveryWorkbench
export FDEX_VENDOR=$PWD/vendor
npm install
bash scripts/ci-build-workbench.sh   # if src lacks node_modules
npm run dist:linux
```

## Code signing

- macOS: `build.mac.identity` is `null` (Gatekeeper will warn). Set Apple Developer identity for distribution.
- Windows: `signAndEditExecutable: false`. Add cert for SmartScreen.

Harness stays **0.1.1-rc.2**.
