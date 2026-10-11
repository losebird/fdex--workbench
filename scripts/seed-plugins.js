#!/usr/bin/env node
/**
 * Seed dsh-our-free-model into DSH_HOME (same idea as Electron fixupDshHome).
 * Idempotent — safe to run on every start. No pnpm required.
 *
 * Env:
 *   FDE_REPO_ROOT  workbench root (has vendor/ + upstream/)
 *   DSH_HOME       defaults to $FDE_REPO_ROOT/.runtime/dsh-home
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
const PLUGIN_NAME = 'dsh-our-free-model';
const WEB_BUNDLES = ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app'];

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
    // Windows without Developer Mode: fall back to directory junction / copy
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

function main() {
  const vendorPlugin = path.join(ROOT, 'vendor', PLUGIN_NAME);
  if (!fs.existsSync(path.join(vendorPlugin, 'package.json'))) {
    console.warn(`seed-plugins: skip — missing ${vendorPlugin}`);
    return;
  }

  fs.mkdirSync(DSH_HOME, { recursive: true });
  const localPlugin = path.join(DSH_HOME, 'bundled-plugins', PLUGIN_NAME);
  fs.mkdirSync(path.dirname(localPlugin), { recursive: true });
  if (!fs.existsSync(path.join(localPlugin, 'package.json'))) {
    copyDir(vendorPlugin, localPlugin);
    console.log(`seed-plugins: copied ${PLUGIN_NAME} → ${localPlugin}`);
  }

  const webDir = path.join(DSH_HOME, 'profiles', 'web');
  const webPkgPath = path.join(webDir, 'package.json');
  fs.mkdirSync(webDir, { recursive: true });

  let pkg;
  if (fs.existsSync(webPkgPath)) {
    pkg = JSON.parse(fs.readFileSync(webPkgPath, 'utf8'));
  } else {
    // Match dsh initProfile for "web" so first start has a real profile.
    pkg = {
      name: 'dsh-profile-web',
      private: true,
      dependencies: {},
      dsh: { profile: { bundles: [...WEB_BUNDLES] } },
    };
    console.log(`seed-plugins: initialized profiles/web at ${webDir}`);
  }

  pkg.dependencies = pkg.dependencies || {};
  pkg.dependencies[PLUGIN_NAME] = `link:${localPlugin}`;
  if (!pkg.dsh) pkg.dsh = { profile: { bundles: [] } };
  if (!pkg.dsh.profile) pkg.dsh.profile = { bundles: [] };
  if (!Array.isArray(pkg.dsh.profile.bundles)) pkg.dsh.profile.bundles = [];
  for (const b of WEB_BUNDLES) {
    if (!pkg.dsh.profile.bundles.includes(b)) pkg.dsh.profile.bundles.push(b);
  }
  if (!pkg.dsh.profile.bundles.includes(PLUGIN_NAME)) {
    pkg.dsh.profile.bundles.push(PLUGIN_NAME);
  }
  fs.writeFileSync(webPkgPath, JSON.stringify(pkg, null, 2) + '\n');

  const patchPath = path.join(webDir, 'cordis.patch.yml');
  if (!fs.existsSync(patchPath)) fs.writeFileSync(patchPath, PROFILE_PATCH_TEMPLATE);
  const wsPath = path.join(webDir, 'pnpm-workspace.yaml');
  if (!fs.existsSync(wsPath)) fs.writeFileSync(wsPath, PROFILE_PNPM_WORKSPACE);

  ensureSymlink(path.join(webDir, 'node_modules', PLUGIN_NAME), localPlugin);
  console.log(`seed-plugins: ${PLUGIN_NAME} on web profile (DSH_HOME=${DSH_HOME})`);
}

main();
