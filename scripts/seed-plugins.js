#!/usr/bin/env node
/**
 * Seed vendor plugins into DSH_HOME (same idea as Electron fixupDshHome).
 * Idempotent — safe to run on every start. No pnpm required.
 *
 * Default: only dsh-our-free-model.
 *
 * Do NOT seed dsh-openapi by default. FDE already registers OpenAPI tools
 * (openapi_list, etc.) via @deepseek-ai/dsh-fde-project. Loading vendor
 * dsh-openapi on top duplicates those tool names and crashes boot with:
 *   tool "openapi_list" is already registered
 *
 * On every start we auto-unseed dsh-openapi from the web profile (unless
 * SEED_OPENAPI=1) so a previous bad seed self-heals.
 *
 * Env:
 *   FDE_REPO_ROOT  workbench root (has vendor/ + upstream/)
 *   DSH_HOME       defaults to $FDE_REPO_ROOT/.runtime/dsh-home
 *   SEED_OPENAPI   set to 1/true/yes to force-seed dsh-openapi (advanced;
 *                  will conflict with fde-project OpenAPI tools)
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = process.env.FDE_REPO_ROOT;
if (!ROOT) {
  console.error('seed-plugins: set FDE_REPO_ROOT to the workbench root');
  process.exit(1);
}

const DSH_HOME = process.env.DSH_HOME || path.join(ROOT, '.runtime', 'dsh-home');
const HARNESS = path.join(ROOT, 'upstream', 'deepseek-harness');
// Default OFF — FDE fde-project already provides OpenAPI tools; seeding
// vendor dsh-openapi duplicates openapi_list and crashes boot.
const SEED_OPENAPI = /^(1|true|yes)$/i.test(String(process.env.SEED_OPENAPI || ''));
const DEFAULT_PLUGINS = ['dsh-our-free-model'];
const WEB_BUNDLES = ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app'];

// Peers declared by vendor/dsh-openapi — link from harness tree so Node can resolve.
const OPENAPI_PEERS = [
  { name: '@deepseek-ai/schemastery', candidates: ['vendor/schemastery'] },
  { name: '@deepseek-ai/cordis', candidates: ['vendor/cordis'] },
  { name: '@deepseek-ai/dsh-tools', candidates: ['packages/core/tools'] },
];

const PROFILE_PATCH_TEMPLATE = `# Your patch layer for this dsh profile, applied after every bundle layer:
# a top-level YAML array of loader patch entries (id-targeted config
# overrides, disables, and insert lists; \`!!js\` expressions allowed).
[]
`;

const PROFILE_PNPM_WORKSPACE = `packages:
  - .

nodeLinker: hoisted
autoInstallPeers: false
`;

function copyDir(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const ent of fs.readdirSync(src, { withFileTypes: true })) {
    if (ent.name === 'node_modules' || ent.name === '.git') continue;
    const from = path.join(src, ent.name);
    const to = path.join(dest, ent.name);
    if (ent.isDirectory()) copyDir(from, to);
    else if (ent.isSymbolicLink()) {
      try {
        fs.symlinkSync(fs.readlinkSync(from), to);
      } catch {
        fs.copyFileSync(from, to);
      }
    } else {
      fs.copyFileSync(from, to);
    }
  }
}

function ensureSymlink(linkPath, target) {
  const absTarget = path.resolve(target);
  fs.mkdirSync(path.dirname(linkPath), { recursive: true });
  try {
    const st = fs.lstatSync(linkPath);
    if (st.isSymbolicLink()) {
      let cur = fs.readlinkSync(linkPath);
      if (!path.isAbsolute(cur)) cur = path.resolve(path.dirname(linkPath), cur);
      if (cur === absTarget) return;
    }
    fs.rmSync(linkPath, { recursive: true, force: true });
  } catch (e) {
    if (e.code !== 'ENOENT') throw e;
  }
  try {
    fs.symlinkSync(absTarget, linkPath);
  } catch (e) {
    if (process.platform === 'win32') {
      try {
        fs.symlinkSync(absTarget, linkPath, 'junction');
        return;
      } catch (_) {}
    }
    console.warn(`seed-plugins: symlink failed (${e.message}); copying instead`);
    copyDir(absTarget, linkPath);
  }
}

function packageJsonAt(dir) {
  return fs.existsSync(path.join(dir, 'package.json'));
}

function resolveInHarnessNodeModules(pkgName) {
  const parts = pkgName.split('/');
  const direct = path.join(HARNESS, 'node_modules', ...parts);
  if (packageJsonAt(direct)) return direct;

  // pnpm layout: node_modules/.pnpm/<name>@*/node_modules/<name>
  const pnpmRoot = path.join(HARNESS, 'node_modules', '.pnpm');
  if (!fs.existsSync(pnpmRoot)) return null;
  const needle = parts[parts.length - 1];
  let entries;
  try {
    entries = fs.readdirSync(pnpmRoot);
  } catch {
    return null;
  }
  const prefix = pkgName.startsWith('@')
    ? `${parts[0]}+${parts[1]}@`
    : `${pkgName}@`;
  // Also match folder names like yaml@2.8.1
  for (const ent of entries) {
    if (!ent.startsWith(prefix) && !(ent.startsWith(`${needle}@`) && !pkgName.startsWith('@'))) {
      continue;
    }
    const cand = path.join(pnpmRoot, ent, 'node_modules', ...parts);
    if (packageJsonAt(cand)) return cand;
  }
  // slower fallback scan
  for (const ent of entries) {
    const cand = path.join(pnpmRoot, ent, 'node_modules', ...parts);
    if (packageJsonAt(cand)) return cand;
  }
  return null;
}

function resolvePeer(relCandidates) {
  for (const rel of relCandidates) {
    const abs = path.join(HARNESS, rel);
    if (packageJsonAt(abs)) return abs;
  }
  return null;
}

function resolvePackage(name, relCandidates = []) {
  const fromCand = resolvePeer(relCandidates);
  if (fromCand) return fromCand;
  return resolveInHarnessNodeModules(name);
}

function linkNamedPackage(localPlugin, name, target) {
  const linkPath = path.join(localPlugin, 'node_modules', ...name.split('/'));
  ensureSymlink(linkPath, target);
  console.log(`seed-plugins: linked ${name} → ${target}`);
}

function ensureNpmDep(localPlugin, name, versionRange) {
  const existing = path.join(localPlugin, 'node_modules', ...name.split('/'));
  if (packageJsonAt(existing)) return true;

  const fromHarness = resolveInHarnessNodeModules(name);
  if (fromHarness) {
    linkNamedPackage(localPlugin, name, fromHarness);
    return true;
  }

  // Last resort: npm install into the plugin (Ace has npm; no pnpm needed).
  const spec = versionRange ? `${name}@${versionRange}` : name;
  const registry =
    process.env.NPM_CONFIG_REGISTRY ||
    process.env.npm_config_registry ||
    'https://registry.npmmirror.com';
  console.log(`seed-plugins: npm install ${spec} into plugin (registry=${registry})`);
  const r = spawnSync(
    'npm',
    ['install', spec, '--omit=dev', '--no-package-lock', '--no-save', '--registry', registry],
    { cwd: localPlugin, encoding: 'utf8', env: { ...process.env, npm_config_registry: registry } },
  );
  if (r.status !== 0) {
    console.warn(`seed-plugins: npm install ${spec} failed: ${(r.stderr || r.stdout || '').slice(0, 400)}`);
    return false;
  }
  return packageJsonAt(existing);
}

function linkOpenapiDeps(localPlugin) {
  const missing = [];

  // Install yaml FIRST — npm install rewrites node_modules and would wipe peer symlinks.
  const yamlOk = ensureNpmDep(localPlugin, 'yaml', '^2.8.1');
  if (!yamlOk) missing.push('yaml');

  // Then link peers from harness (must survive after any npm install).
  for (const peer of OPENAPI_PEERS) {
    const target = resolvePackage(peer.name, peer.candidates);
    if (!target) {
      missing.push(peer.name);
      console.warn(`seed-plugins: peer missing for openapi: ${peer.name}`);
      continue;
    }
    linkNamedPackage(localPlugin, peer.name, target);
  }

  return missing;
}

function unseedPlugin(pluginName, pkg) {
  let changed = false;
  if (pkg.dependencies && pkg.dependencies[pluginName]) {
    delete pkg.dependencies[pluginName];
    changed = true;
  }
  if (pkg.dsh?.profile?.bundles) {
    const before = pkg.dsh.profile.bundles.length;
    pkg.dsh.profile.bundles = pkg.dsh.profile.bundles.filter((b) => b !== pluginName);
    if (pkg.dsh.profile.bundles.length !== before) changed = true;
  }

  const localPlugin = path.join(DSH_HOME, 'bundled-plugins', pluginName);
  if (fs.existsSync(localPlugin)) {
    fs.rmSync(localPlugin, { recursive: true, force: true });
    changed = true;
    console.log(`seed-plugins: removed ${localPlugin}`);
  }

  const webLink = path.join(DSH_HOME, 'profiles', 'web', 'node_modules', pluginName);
  try {
    if (fs.lstatSync(webLink)) {
      fs.rmSync(webLink, { recursive: true, force: true });
      changed = true;
    }
  } catch (e) {
    if (e.code !== 'ENOENT') throw e;
  }

  if (changed) {
    console.log(`seed-plugins: unseeded ${pluginName} from web profile`);
  }
  return changed;
}

function seedPlugin(pluginName, pkg, { withOpenapiDeps = false } = {}) {
  const vendorPlugin = path.join(ROOT, 'vendor', pluginName);
  if (!packageJsonAt(vendorPlugin)) {
    console.warn(`seed-plugins: skip — missing ${vendorPlugin}`);
    return false;
  }

  const localPlugin = path.join(DSH_HOME, 'bundled-plugins', pluginName);
  fs.mkdirSync(path.dirname(localPlugin), { recursive: true });
  // Refresh plugin sources (keep node_modules we manage for deps)
  const keptNm = path.join(localPlugin, 'node_modules');
  const nmBackup = path.join(DSH_HOME, '.seed-nm-backup', pluginName);
  if (fs.existsSync(keptNm)) {
    fs.mkdirSync(path.dirname(nmBackup), { recursive: true });
    fs.rmSync(nmBackup, { recursive: true, force: true });
    fs.renameSync(keptNm, nmBackup);
  }
  fs.rmSync(localPlugin, { recursive: true, force: true });
  copyDir(vendorPlugin, localPlugin);
  if (fs.existsSync(nmBackup)) {
    fs.renameSync(nmBackup, keptNm);
  }
  console.log(`seed-plugins: synced ${pluginName} → ${localPlugin}`);

  if (withOpenapiDeps) {
    const missing = linkOpenapiDeps(localPlugin);
    // schemastery is fatal for boot — do not leave a half-seeded openapi
    if (missing.includes('@deepseek-ai/schemastery')) {
      console.error(
        'seed-plugins: cannot seed dsh-openapi — @deepseek-ai/schemastery not found under harness. Run npm run setup:workbench first, or SEED_OPENAPI=0 to skip.',
      );
      unseedPlugin(pluginName, pkg);
      return false;
    }
    if (missing.length) {
      console.warn(`seed-plugins: openapi seeded with missing deps: ${missing.join(', ')} (boot may still fail)`);
    }
  }

  pkg.dependencies = pkg.dependencies || {};
  pkg.dependencies[pluginName] = `link:${localPlugin}`;
  if (!pkg.dsh) pkg.dsh = { profile: { bundles: [] } };
  if (!pkg.dsh.profile) pkg.dsh.profile = { bundles: [] };
  if (!Array.isArray(pkg.dsh.profile.bundles)) pkg.dsh.profile.bundles = [];
  if (!pkg.dsh.profile.bundles.includes(pluginName)) {
    pkg.dsh.profile.bundles.push(pluginName);
  }

  const webDir = path.join(DSH_HOME, 'profiles', 'web');
  ensureSymlink(path.join(webDir, 'node_modules', pluginName), localPlugin);
  console.log(`seed-plugins: ${pluginName} on web profile (DSH_HOME=${DSH_HOME})`);
  return true;
}

function main() {
  fs.mkdirSync(DSH_HOME, { recursive: true });

  const webDir = path.join(DSH_HOME, 'profiles', 'web');
  const webPkgPath = path.join(webDir, 'package.json');
  fs.mkdirSync(webDir, { recursive: true });

  let pkg;
  if (fs.existsSync(webPkgPath)) {
    pkg = JSON.parse(fs.readFileSync(webPkgPath, 'utf8'));
  } else {
    pkg = {
      name: 'dsh-profile-web',
      private: true,
      dependencies: {},
      dsh: { profile: { bundles: [...WEB_BUNDLES] } },
    };
    console.log(`seed-plugins: initialized profiles/web at ${webDir}`);
  }

  pkg.dependencies = pkg.dependencies || {};
  if (!pkg.dsh) pkg.dsh = { profile: { bundles: [] } };
  if (!pkg.dsh.profile) pkg.dsh.profile = { bundles: [] };
  if (!Array.isArray(pkg.dsh.profile.bundles)) pkg.dsh.profile.bundles = [];
  for (const b of WEB_BUNDLES) {
    if (!pkg.dsh.profile.bundles.includes(b)) pkg.dsh.profile.bundles.push(b);
  }

  for (const name of DEFAULT_PLUGINS) {
    seedPlugin(name, pkg);
  }

  if (SEED_OPENAPI) {
    seedPlugin('dsh-openapi', pkg, { withOpenapiDeps: true });
  } else {
    // Always strip leftover openapi so boot does not hit
    // "tool openapi_list is already registered" vs fde-project.
    unseedPlugin('dsh-openapi', pkg);
    console.log('seed-plugins: dsh-openapi not seeded (FDE OpenAPI via fde-project; set SEED_OPENAPI=1 only if you know you need the vendor plugin)');
  }

  fs.writeFileSync(webPkgPath, JSON.stringify(pkg, null, 2) + '\n');

  const patchPath = path.join(webDir, 'cordis.patch.yml');
  if (!fs.existsSync(patchPath)) fs.writeFileSync(patchPath, PROFILE_PATCH_TEMPLATE);
  const wsPath = path.join(webDir, 'pnpm-workspace.yaml');
  if (!fs.existsSync(wsPath)) fs.writeFileSync(wsPath, PROFILE_PNPM_WORKSPACE);
}

main();
