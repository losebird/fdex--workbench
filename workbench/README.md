# FDE-X 交付工作台（源码）

DeepSeek Harness **0.1.1-rc.2** + FDE 插件。侧栏收起遮罩已修（`.fading { pointer-events: none }`）。

## 本机跑起来

在**仓库根目录**（只需 Node + npm，**不要**全局装 pnpm）：

```bash
git clone https://github.com/losebird/fdex--workbench.git
cd fdex--workbench

# 建议 Node 24；国内：
export NPM_CONFIG_REGISTRY=https://registry.npmmirror.com

npm run setup:workbench   # = npx pnpm@11.7.0 install + build
npm run start:workbench   # 起 dsh web 并打开浏览器
```

默认 `http://127.0.0.1:3080`。改端口：`FDEX_PORT=3081 npm run start:workbench`。

## 说明

- **setup**：用 `npx --yes pnpm@11.7.0`，不依赖 corepack / 全局 pnpm。
- **start**：只调用 `node` 跑已 build 的 dsh 入口。
- harness 是 pnpm monorepo，不能对它单独 `npm install` 代替 setup。
- `@pnpm/exe` 下载失败时设 `NPM_CONFIG_REGISTRY=https://registry.npmmirror.com` 再跑 setup。
