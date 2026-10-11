'use strict';

const { app, BrowserWindow, dialog, shell, Menu } = require('electron');
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');
const http = require('http');

const PORT = Number(process.env.FDEX_PORT || 3080);
const HOST = '127.0.0.1';
const DSH_CLIENT_COMMIT_HASH = '337cd32a63a7042ccfd2ade412619ee41441f4c1';

let mainWindow = null;
let serverProc = null;
let shuttingDown = false;

function resourcesRoot() {
  if (app.isPackaged) return process.resourcesPath;
  return path.join(__dirname, '..', 'staging');
}

function brandPath(...parts) {
  if (app.isPackaged) return path.join(process.resourcesPath, 'brand', ...parts);
  return path.join(__dirname, '..', 'resources', 'brand', ...parts);
}

function workbenchRoot() {
  return path.join(resourcesRoot(), 'workbench');
}

function harnessRoot() {
  return path.join(workbenchRoot(), 'upstream', 'deepseek-harness');
}

function bundledNodeBinary() {
  const root = path.join(resourcesRoot(), 'node');
  if (process.platform === 'win32') return path.join(root, 'node.exe');
  return path.join(root, 'bin', 'node');
}

function userDshHome() {
  return path.join(app.getPath('userData'), 'dsh-home');
}

function copyDirLimited(src, dest, opts = {}) {
  fs.mkdirSync(dest, { recursive: true });
  for (const ent of fs.readdirSync(src, { withFileTypes: true })) {
    if (opts.skipNames && opts.skipNames.has(ent.name)) continue;
    const s = path.join(src, ent.name);
    const d = path.join(dest, ent.name);
    if (ent.isDirectory()) copyDirLimited(s, d, opts);
    else if (ent.isSymbolicLink()) {
      try {
        fs.symlinkSync(fs.readlinkSync(s), d);
      } catch (_) {
        try { fs.copyFileSync(s, d); } catch (__) {}
      }
    } else {
      fs.copyFileSync(s, d);
    }
  }
}

function rewriteSymlinksUnder(rootDir, rewriteFn) {
  if (!fs.existsSync(rootDir)) return 0;
  let n = 0;
  const walk = (dir) => {
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); }
    catch (_) { return; }
    for (const ent of entries) {
      const full = path.join(dir, ent.name);
      if (ent.isSymbolicLink()) {
        let target;
        try { target = fs.readlinkSync(full); } catch (_) { continue; }
        const next = rewriteFn(target, full);
        if (next && next !== target) {
          try {
            fs.unlinkSync(full);
            fs.symlinkSync(next, full);
            n += 1;
          } catch (_) {}
        }
      } else if (ent.isDirectory()) {
        // Do not descend into enormous package trees that are real dirs inside .pnpm
        if (ent.name === '.pnpm' || ent.name === 'sessions' || ent.name === 'storages') continue;
        walk(full);
      }
    }
  };
  walk(rootDir);
  return n;
}

function fixupDshHome(dest, harness, workbench) {
  fs.mkdirSync(dest, { recursive: true });
  const seed = path.join(workbench, '.runtime', 'dsh-home');
  const marker = path.join(dest, '.fdex-seeded');

  if (!fs.existsSync(marker) && fs.existsSync(seed)) {
    copyDirLimited(seed, dest, {
      skipNames: new Set(['sessions', 'storages', '.credentials.yaml']),
    });
    fs.writeFileSync(marker, new Date().toISOString(), 'utf8');
  }

  // Bundle plugin into DSH_HOME for stable offline resolve
  const vendorPlugin = path.join(workbench, 'vendor', 'dsh-our-free-model');
  const localPlugin = path.join(dest, 'bundled-plugins', 'dsh-our-free-model');
  if (fs.existsSync(vendorPlugin)) {
    fs.mkdirSync(path.dirname(localPlugin), { recursive: true });
    if (!fs.existsSync(path.join(localPlugin, 'package.json'))) {
      copyDirLimited(vendorPlugin, localPlugin);
    }
  }

  const webPkgPath = path.join(dest, 'profiles', 'web', 'package.json');
  if (fs.existsSync(webPkgPath) && fs.existsSync(localPlugin)) {
    try {
      const pkg = JSON.parse(fs.readFileSync(webPkgPath, 'utf8'));
      pkg.dependencies = pkg.dependencies || {};
      pkg.dependencies['dsh-our-free-model'] = `link:${localPlugin}`;
      if (!pkg.dsh) pkg.dsh = { profile: { bundles: [] } };
      if (!pkg.dsh.profile) pkg.dsh.profile = { bundles: [] };
      if (!Array.isArray(pkg.dsh.profile.bundles)) pkg.dsh.profile.bundles = [];
      if (!pkg.dsh.profile.bundles.includes('dsh-our-free-model')) {
        pkg.dsh.profile.bundles.push('dsh-our-free-model');
      }
      fs.writeFileSync(webPkgPath, JSON.stringify(pkg, null, 2) + '\n');
    } catch (_) {}

    const linkDir = path.join(dest, 'profiles', 'web', 'node_modules');
    fs.mkdirSync(linkDir, { recursive: true });
    const linkPath = path.join(linkDir, 'dsh-our-free-model');
    try { fs.rmSync(linkPath, { recursive: true, force: true }); } catch (_) {}
    try { fs.symlinkSync(localPlugin, linkPath); } catch (_) {}
  }

  // Rewrite absolute symlinks that pointed at the build-machine harness path
  const harnessMarkers = [
    '/upstream/deepseek-harness',
    'deepseek-harness',
  ];
  rewriteSymlinksUnder(path.join(dest, 'profiles'), (target) => {
    // Absolute links into old FDEDeliveryWorkbench harness
    const idx = target.indexOf('/upstream/deepseek-harness');
    if (idx !== -1) {
      const rest = target.slice(idx + '/upstream/deepseek-harness'.length);
      return path.join(harness, rest.replace(/^\//, ''));
    }
    // Absolute /workspace/fde-workbench/vendor/...
    const vidx = target.indexOf('/fde-workbench/vendor/');
    if (vidx !== -1) {
      const rest = target.slice(vidx + '/fde-workbench/vendor/'.length);
      return path.join(workbench, 'vendor', rest);
    }
    if (target.includes('dsh-our-free-model') && fs.existsSync(localPlugin)) {
      if (target.endsWith('dsh-our-free-model') || target.includes('/dsh-our-free-model')) {
        return localPlugin;
      }
    }
    return target;
  });

  return { localPlugin };
}

function waitForHttp(url, timeoutMs) {
  const start = Date.now();
  return new Promise((resolve, reject) => {
    const tick = () => {
      if (shuttingDown) return reject(new Error('shutting down'));
      const req = http.get(url, (res) => {
        res.resume();
        if (res.statusCode && res.statusCode < 500) resolve();
        else retry();
      });
      req.on('error', retry);
      req.setTimeout(2000, () => {
        req.destroy();
        retry();
      });
    };
    const retry = () => {
      if (Date.now() - start > timeoutMs) reject(new Error('server start timeout'));
      else setTimeout(tick, 500);
    };
    tick();
  });
}

function resolveDshEntry() {
  const harness = harnessRoot();
  const candidates = [
    path.join(harness, 'apps', 'cli', 'lib', 'bin.js'),
    path.join(harness, 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) return c;
  }
  throw new Error('dsh CLI entry not found under harness');
}

function startServer() {
  const harness = harnessRoot();
  const workbench = workbenchRoot();
  const nodeBin = bundledNodeBinary();
  const dshHome = userDshHome();

  if (!fs.existsSync(nodeBin)) throw new Error(`Bundled Node not found: ${nodeBin}`);
  if (!fs.existsSync(harness)) throw new Error(`Harness not found: ${harness}`);

  fixupDshHome(dshHome, harness, workbench);

  const entry = resolveDshEntry();
  const args = [entry, 'web', '--no-open', '--host', HOST, '--port', String(PORT)];

  const env = {
    ...process.env,
    DSH_HOME: dshHome,
    DSH_CLIENT_COMMIT_HASH,
    FDE_REPO_ROOT: workbench,
  };
  delete env.ELECTRON_RUN_AS_NODE;

  const logDir = path.join(app.getPath('userData'), 'logs');
  fs.mkdirSync(logDir, { recursive: true });
  const logPath = path.join(logDir, 'dsh-web.log');
  const logFd = fs.openSync(logPath, 'a');

  serverProc = spawn(nodeBin, args, {
    cwd: harness,
    env,
    stdio: ['ignore', logFd, logFd],
    windowsHide: true,
  });

  serverProc.on('exit', (code, signal) => {
    serverProc = null;
    if (!shuttingDown && mainWindow && !mainWindow.isDestroyed()) {
      dialog.showErrorBox(
        'FDE-X Workbench',
        `后台服务已退出 (code=${code}, signal=${signal}).\n日志: ${logPath}`
      );
    }
  });

  return { logPath, dshHome };
}

function stopServer() {
  if (!serverProc) return;
  const proc = serverProc;
  serverProc = null;
  try {
    if (process.platform === 'win32') {
      spawn('taskkill', ['/pid', String(proc.pid), '/f', '/t']);
    } else {
      proc.kill('SIGTERM');
      setTimeout(() => {
        try { proc.kill('SIGKILL'); } catch (_) {}
      }, 3000).unref?.();
    }
  } catch (_) {}
}

function createWindow() {
  const iconFile = brandPath('icon.png');
  const opts = {
    width: 1440,
    height: 900,
    minWidth: 1024,
    minHeight: 680,
    title: 'FDE-X 交付工作台',
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  };
  if (fs.existsSync(iconFile)) opts.icon = iconFile;

  mainWindow = new BrowserWindow(opts);
  mainWindow.once('ready-to-show', () => mainWindow.show());
  mainWindow.on('closed', () => { mainWindow = null; });
  mainWindow.loadURL(`http://${HOST}:${PORT}`);
  mainWindow.webContents.setWindowOpenHandler(({ url: target }) => {
    shell.openExternal(target);
    return { action: 'deny' };
  });
}

function buildMenu() {
  const template = [
    {
      label: 'FDE-X',
      submenu: [
        {
          label: '打开工作台',
          click: () => {
            if (mainWindow) { mainWindow.show(); mainWindow.focus(); }
            else createWindow();
          },
        },
        {
          label: '在浏览器打开',
          click: () => shell.openExternal(`http://${HOST}:${PORT}`),
        },
        { type: 'separator' },
        {
          label: '打开用户数据目录',
          click: () => shell.openPath(app.getPath('userData')),
        },
        { type: 'separator' },
        { role: process.platform === 'darwin' ? 'close' : 'quit', label: '退出' },
      ],
    },
    { role: 'editMenu' },
    { role: 'viewMenu' },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

async function boot() {
  buildMenu();
  let logPath = '';
  try {
    ({ logPath } = startServer());
  } catch (err) {
    dialog.showErrorBox('FDE-X Workbench 启动失败', String(err && err.message ? err.message : err));
    app.quit();
    return;
  }

  try {
    await waitForHttp(`http://${HOST}:${PORT}/`, 180000);
  } catch (err) {
    dialog.showErrorBox(
      'FDE-X Workbench',
      `服务未能在 180s 内就绪。\n${err}\n日志: ${logPath}`
    );
    app.quit();
    return;
  }

  createWindow();
}

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });

  app.whenReady().then(boot);

  app.on('before-quit', () => {
    shuttingDown = true;
    stopServer();
  });

  app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') {
      shuttingDown = true;
      stopServer();
      app.quit();
    }
  });

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0 && !shuttingDown) createWindow();
  });
}
