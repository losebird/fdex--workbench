# FDE-X 交付工作台（源码）

DeepSeek Harness **0.1.1-rc.2** + FDE 插件。侧栏收起遮罩已修（`.fading { pointer-events: none }`）。

## 本机跑起来（推荐）

在**仓库根目录**用 npm 脚本（内部会调 pnpm 装 monorepo，你日常仍可用 npm）：

```bash
git clone https://github.com/losebird/fdex--workbench.git
cd fdex--workbench

# 建议 Node 24（nvm use 24）
npm run setup:workbench   # = pnpm install + build（只需这一次）
npm run start:workbench   # 起 dsh web 并打开浏览器
```

或直接：

```bash
export FDE_REPO_ROOT="$PWD/workbench"
./scripts/setup-workbench.sh
./scripts/start-workbench.sh
```

默认 `http://127.0.0.1:3080`。端口占用可：`FDEX_PORT=3081 npm run start:workbench`。

## 为什么不能只用 npm install？

`upstream/deepseek-harness` 是 **pnpm workspace**（`pnpm-lock.yaml`、`link:` overrides、`packageManager: pnpm@11.7.0`）。  
`npm install` 装不全 monorepo 链接，容易缺 `tsx` 等工具。  
`setup:workbench` 用 Node 自带的 **corepack** 临时启用 pnpm，不要求你改掉平时用 npm 的习惯。  
装好之后，**启动只依赖 `node`**，不再需要 npm/pnpm。

国内网络：脚本默认 `registry.npmmirror.com`；也可：

```bash
export COREPACK_NPM_REGISTRY=https://registry.npmmirror.com
export PNPM_REGISTRY=https://registry.npmmirror.com
```

## 目录

```
workbench/
  upstream/deepseek-harness/   # 主体
  vendor/dsh-openapi/          # OpenAPI 工具（相对 link）
  vendor/dsh-our-free-model/   # 免费模型插件（可选，装进 DSH_HOME）
  frontend/
  start.sh                     # 等价于仓库 scripts/start-workbench.sh
```

`node_modules` / `.runtime` 不进 git；首次 `setup` 后本地生成。
