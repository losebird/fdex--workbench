#!/usr/bin/env node
/**
 * Seed vendor plugins into DSH_HOME (same idea as Electron fixupDshHome).
 * Idempotent — safe to run on every start. No pnpm required.
 *
 * Default: only dsh-our-free-model (matches Electron).
 * dsh-openapi needs peer deps (@deepseek-ai/schemastery etc.) and will crash
 * boot if copied into bundled-plugins without them — so it is NOT seeded by
 * default. Set SEED_OPENAPI=1 to install it with peer symlinks from harness.
 *
 * Also removes a previously seeded dsh-openapi from the web profile so a
 * broken install self-heals on the next start (unless SEED_OPENAPI=1).
 *
 * Env:
 *   FDE_REPO_ROOT  workbench root (has vendor/ + upstream/)
 *   DSH_HOME       defaults to $FDE_REPO_ROOT/.runtime/dsh-home
 *   SEED_OPENAPI   set to 1 to also seed dsh-openapi with peer links
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = process.env.FDE_REPO_ROOT;
if (!ROOT) {
  console.error('seed-plugins: set FDE_REPO_ROOT to the workbench root');
  process.exit(1);
}

const DSH_HOME = process.env.DSH_HOME || path.join(ROOT, '.runtime', 'dsh-home');
const HARNESS = path.join(ROOT, 'upstream', 'deepseek-harness');
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
  fs.mkdirSync(path.dirname(linkPath), { recursive: true });
  try {
    const st = fs.lstatSync(linkPath);
    if (st.isSymbolicLink() && fs.readlinkSync(linkPath) === target) return;
    fs.rmSync(linkPath, { recursive: true, force: true });
  } catch (e) {
    if (e.code !== 'ENOENT') throw e;
  }
  try {
    fs.symlinkSync(target, linkPath);
  } catch (e) {
    if (process.platform === 'win32') {
      try {
        fs.symlinkSync(target, linkPath, 'junction');
        return;
      } catch (_) {}
    }
    console.warn(`seed-plugins: symlink failed (${e.message}); copying instead`);
    copyDir(target, linkPath);
  }
}

function resolvePeer(relCandidates) {
  for (const rel of relCandidates) {
    const abs = path.join(HARNESS, rel);
    if (fs.existsSync(path.join(abs, 'package.json'))) return abs;
  }
  return null;
}

function linkOpenapiPeers(localPlugin) {
  for (const peer of OPENAPI_PEERS) {
    let target = resolvePeer(peer.candidates);
    if (!target) {
      const nm = path.join(HARNESS, 'node_modules', ...peer.name.split('/'));
      if (fs.existsSync(path.join(nm, 'package.json'))) target = nm;
    }
    if (!target) {
      console.warn(`seed-plugins: peer missing for openapi: ${peer.name}`);
      continue;
    }
    const linkPath = path.join(localPlugin, 'node_modules', ...peer.name.split('/'));
    ensureSymlink(linkPath, target);
    console.log(`seed-plugins: linked peer ${peer.name} → ${target}`);
  }
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
    console.log(`seed-plugins: removed broken ${localPlugin}`);
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
    console.log(`seed-plugins: unseeded ${pluginName} from web profile (was breaking boot without peers)`);
  }
  return changed;
}

function seedPlugin(pluginName, pkg, { withOpenapiPeers = false } = {}) {
  const vendorPlugin = path.join(ROOT, 'vendor', pluginName);
  if (!fs.existsSync(path.join(vendorPlugin, 'package.json'))) {
    console.warn(`seed-plugins: skip — missing ${vendorPlugin}`);
    return false;
  }

  const localPlugin = path.join(DSH_HOME, 'bundled-plugins', pluginName);
  fs.mkdirSync(path.dirname(localPlugin), { recursive: true });
  if (!fs.existsSync(path.join(localPlugin, 'package.json'))) {
    copyDir(vendorPlugin, localPlugin);
    console.log(`seed-plugins: copied ${pluginName} → ${localPlugin}`);
  }

  if (withOpenapiPeers) {
    linkOpenapiPeers(localPlugin);
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

  // Heal: drop openapi unless explicitly requested (missing schemastery peers crash boot).
  if (!SEED_OPENAPI) {
    unseedPlugin('dsh-openapi', pkg);
  }

  for (const name of DEFAULT_PLUGINS) {
    seedPlugin(name, pkg);
  }

  if (SEED_OPENAPI) {
    seedPlugin('dsh-openapi', pkg, { withOpenapiPeers: true });
  }

  fs.writeFileSync(webPkgPath, JSON.stringify(pkg, null, 2) + '\n');

  const patchPath = path.join(webDir, 'cordis.patch.yml');
  if (!fs.existsSync(patchPath)) fs.writeFileSync(patchPath, PROFILE_PATCH_TEMPLATE);
  const wsPath = path.join(webDir, 'pnpm-workspace.yaml');
  if (!fs.existsSync(wsPath)) fs.writeFileSync(wsPath, PROFILE_PNPM_WORKSPACE);
}

main();
