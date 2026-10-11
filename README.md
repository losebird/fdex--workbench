# FDE-X Workbench Desktop Installer

Electron + electron-builder packaging for **FDE-X 交付工作台** (DeepSeek Harness **0.1.1-rc.2** + FDE plugins).

Repo: https://github.com/losebird/fdex--workbench

> **NOTICE:** Lab / course materials redistribution may require a **private** repo. See [NOTICE.md](./NOTICE.md).  
> Recommendation: `gh repo edit losebird/fdex--workbench --visibility private` before relying on the `workbench-src` release asset for anything beyond private packaging.

## What CI builds

| Artifact | Runner | Notes |
|----------|--------|--------|
| `.dmg` / `.zip` | `macos-latest` | unsigned (`identity: null`) |
| NSIS `.exe` / `.msi` | `windows-latest` | x64 |

The giant workbench `node_modules` is **not** committed. CI downloads `workbench-src.tar.zst` from Release tag **`workbench-src-v0.1.0`**, runs `pnpm install` + `build` on that OS, then packages.

## Enable GitHub Actions (one-time)

The OAuth token used by this agent **cannot** push files under `.github/workflows/` (missing `workflow` scope). The workflow YAML is stored at:

**[`ci/build-desktop.yml`](./ci/build-desktop.yml)**

Enable it once (GitHub website, logged in as Ace/`losebird`):

1. Open https://github.com/losebird/fdex--workbench/new/main?filename=.github/workflows/build-desktop.yml
2. Paste the contents of `ci/build-desktop.yml`
3. Commit to `main`

Or with a PAT that has the `workflow` scope:

```bash
mkdir -p .github/workflows
cp ci/build-desktop.yml .github/workflows/build-desktop.yml
git add .github/workflows/build-desktop.yml
git commit -m "Enable desktop installer workflow"
git push
```

## Trigger a build (Ace)

After the workflow file exists:

1. Confirm release asset: https://github.com/losebird/fdex--workbench/releases/tag/workbench-src-v0.1.0
2. **Actions** → **Build desktop installers** → **Run workflow**  
   or:

```bash
gh workflow run build-desktop.yml -R losebird/fdex--workbench
gh run list -R losebird/fdex--workbench --workflow=build-desktop.yml
```

3. Download artifacts from the run: `FDE-X-Workbench-macos-dmg`, `FDE-X-Workbench-windows-installer`

## Layout

```
src/                     Electron main/preload
scripts/                 stage / fetch-node / CI fetch+build / pack-workbench-src
vendor/                  dsh-openapi + dsh-our-free-model (small)
resources/brand/         FDE-X logo
ci/build-desktop.yml     workflow template (copy to .github/workflows/)
workbench-src/           (gitignored — CI download)
staging/                 (gitignored — generated)
```

See [BUILD.md](./BUILD.md).
