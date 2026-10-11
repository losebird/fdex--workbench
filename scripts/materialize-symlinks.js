#!/usr/bin/env node
'use strict';
/**
 * Replace symlinks under <dir> with real files/dirs, without following cycles.
 * Needed so WiX/MSI (and some NSIS paths) can see concrete paths under extraResources.
 */
const fs = require('fs');
const path = require('path');

const root = process.argv[2];
if (!root) {
  console.error('usage: materialize-symlinks.js <dir>');
  process.exit(2);
}

let replaced = 0;
let skippedCycles = 0;
let removedBroken = 0;

function copyFile(src, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}

function copyDirSafe(srcDir, destDir, ancestors) {
  let real;
  try {
    real = fs.realpathSync(srcDir);
  } catch {
    fs.mkdirSync(destDir, { recursive: true });
    removedBroken++;
    return;
  }
  if (ancestors.has(real)) {
    fs.mkdirSync(destDir, { recursive: true });
    skippedCycles++;
    return;
  }
  const next = new Set(ancestors);
  next.add(real);
  fs.mkdirSync(destDir, { recursive: true });
  let names;
  try {
    names = fs.readdirSync(srcDir);
  } catch {
    return;
  }
  for (const name of names) {
    const s = path.join(srcDir, name);
    const d = path.join(destDir, name);
    let st;
    try {
      st = fs.lstatSync(s);
    } catch {
      continue;
    }
    if (st.isSymbolicLink()) {
      let target;
      try {
        target = fs.realpathSync(s);
      } catch {
        removedBroken++;
        continue;
      }
      let tst;
      try {
        tst = fs.statSync(target);
      } catch {
        removedBroken++;
        continue;
      }
      if (tst.isDirectory()) {
        copyDirSafe(target, d, next);
      } else {
        copyFile(target, d);
        replaced++;
      }
    } else if (st.isDirectory()) {
      copyDirSafe(s, d, next);
    } else if (st.isFile() || st.isFIFO() || st.isSocket()) {
      try {
        copyFile(s, d);
      } catch {
        /* ignore exotic */
      }
    }
  }
}

function materializeInPlace(dir, ancestors) {
  let entries;
  try {
    entries = fs.readdirSync(dir);
  } catch {
    return;
  }
  for (const name of entries) {
    const p = path.join(dir, name);
    let st;
    try {
      st = fs.lstatSync(p);
    } catch {
      continue;
    }
    if (st.isSymbolicLink()) {
      let target;
      try {
        target = fs.realpathSync(p);
      } catch {
        fs.rmSync(p, { force: true });
        removedBroken++;
        continue;
      }
      let tst;
      try {
        tst = fs.statSync(target);
      } catch {
        fs.rmSync(p, { force: true });
        removedBroken++;
        continue;
      }
      fs.rmSync(p, { force: true });
      if (tst.isDirectory()) {
        copyDirSafe(target, p, ancestors);
        replaced++;
      } else {
        copyFile(target, p);
        replaced++;
      }
    } else if (st.isDirectory()) {
      let real;
      try {
        real = fs.realpathSync(p);
      } catch {
        continue;
      }
      if (ancestors.has(real)) continue;
      const next = new Set(ancestors);
      next.add(real);
      materializeInPlace(p, next);
    }
  }
}

const abs = path.resolve(root);
console.log('[materialize] root=', abs);
materializeInPlace(abs, new Set());
console.log(
  `[materialize] replaced=${replaced} cycleStubs=${skippedCycles} brokenRemoved=${removedBroken}`
);
