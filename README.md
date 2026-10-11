# FDE-X Workbench Desktop Installer

Electron + electron-builder packaging for **FDE-X 交付工作台** (DeepSeek Harness **0.1.1-rc.2** + FDE plugins).

Repo: https://github.com/losebird/fdex--workbench

> **NOTICE:** Lab / course materials redistribution may require a **private** repo. See [NOTICE.md](./NOTICE.md).

## What CI builds

| Artifact | Runner | Notes |
|----------|--------|--------|
| `.dmg` / `.zip` | `macos-latest` | unsigned (`identity: null`) |
| NSIS `.exe` / `.msi` | `windows-latest` | x64 |

The giant workbench `node_modules` is **not** committed. CI downloads `workbench-src` from a GitHub Release asset, runs `pnpm install` + `build` on that OS, then packages.

## Trigger a build (Ace)

1. Ensure release tag **`workbench-src-v0.1.0`** exists with asset **`workbench-src.tar.zst`** (see BUILD.md).
2. Open **Actions** → **Build desktop installers** → **Run workflow**, or push a tag `v0.1.0`, or push to `main`.
3. Download artifacts from the workflow run: `FDE-X-Workbench-*-dmg`, `FDE-X-Workbench-*-win`.

```bash
gh workflow run build-desktop.yml -R losebird/fdex--workbench
gh run watch -R losebird/fdex--workbench
```

## Local (installer shell only)

```bash
npm install
# after workbench-src is fetched+built:
npm run dist:mac:ci   # on macOS
npm run dist:win:ci   # on Windows
```

## Layout

```
src/                     Electron main/preload
scripts/                 stage / fetch-node / CI fetch+build
vendor/                  dsh-openapi + dsh-our-free-model (small)
resources/brand/         FDE-X logo
.github/workflows/       build-desktop.yml
workbench-src/           (gitignored — CI download)
staging/                 (gitignored — generated)
```
