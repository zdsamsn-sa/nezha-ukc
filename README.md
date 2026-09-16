# 哪吒监控 → Unikraft Cloud 完整部署教程

将 **官方哪吒 Dashboard**（`ghcr.io/nezhahq/nezha`）部署到 [Unikraft Cloud](https://unikraft.cloud)，可选内置 **Nezha Aurora** 现代用户前端。

本方案对照整合了：

| 来源包 | 作用 |
|--------|------|
| **nezha-fly-master** | Fly.io 部署哪吒的思路：官方镜像 + 持久卷 `/dashboard/data` + 端口 8008 |
| **nezha-aurora-main** | 哪吒用户前端主题（纯静态 SPA），注入到 `/dashboard/user-dist` |

---

## 目录

1. [原理与可行性](#1-原理与可行性)
2. [你将得到什么](#2-你将得到什么)
3. [准备条件](#3-准备条件)
4. [首次部署（逐步）](#4-首次部署逐步)
5. [首次登录与面板配置](#5-首次登录与面板配置)
6. [安装 Agent（被控端）](#6-安装-agent被控端)
7. [自定义域名](#7-自定义域名)
8. [更新 / 回滚 / 删除](#8-更新--回滚--删除)
9. [与 Fly.io 方案对照](#9-与-flyio-方案对照)
10. [目录结构](#10-目录结构)
11. [故障排查](#11-故障排查)
12. [安全建议](#12-安全建议)
13. [限制说明](#13-限制说明)

---

## 1. 原理与可行性

### Unikraft Cloud 特点

- 运行 **unikernel 实例**，不是完整 Linux VPS。
- 适合「一个主进程 + 监听端口」；无 systemd、无 Docker-in-Docker、不能随意 `apt install`。
- 对外自动提供 `https://*.地区.unikraft.app`，443 上 TLS 终止后转到容器内端口。

### 为什么哪吒能上 UKC

与 `nezha-fly` 相同，哪吒官方镜像本质是：

```text
进程: /dashboard/app（或镜像 ENTRYPOINT）
监听: 8008
数据: /dashboard/data（config.yaml、sqlite 等）
```

UKC 用 `anyimage` 思路把 OCI 镜像展成 rootfs → 构建 unikernel 镜像 → `unikraft run` 启动，并挂 Volume 到 `/dashboard/data`。

### Aurora 如何生效

哪吒会优先读取本地 **`/dashboard/user-dist`** 作为用户前端（与 Lotus 等主题相同机制）。  
CI 构建时把 Aurora 的 `dist/*` 拷进镜像该目录，打开站点根路径即为 Aurora；`/dashboard` 仍是管理后台。

### 可用性结论

| 能力 | 状态 |
|------|------|
| Web 前台（官方或 Aurora） | ✅ |
| 管理后台 `/dashboard` | ✅ |
| 数据持久化 | ✅ Volume → `/dashboard/data` |
| 重部署保留配置/服务器列表 | ✅（同地区同卷名） |
| Agent 上报 | ⚠️ 通常可用：对接 `域名:443` + TLS；个别环境需自测 |
| 多地区共享同一数据库 | ❌ 每地区独立 Volume |

---

## 2. 你将得到什么

部署成功后：

```text
https://xxxx.sin.unikraft.app/           → 用户状态页（Aurora 或官方）
https://xxxx.sin.unikraft.app/dashboard  → 管理后台
```

默认账号：**admin / admin**（登录后必须立即修改）。

---

## 3. 准备条件

### 3.1 账号

1. **GitHub** 账号（用于放本仓库 + Actions）
2. **Unikraft Cloud** 账号，并在控制台创建 **API Token**  
   （Settings → API Keys）

### 3.2 本仓库

解压 `nezha-ukc.zip` 后推到 GitHub（建议 **Private**）：

```bash
cd nezha-ukc
git init
git add .
git commit -m "Nezha on Unikraft Cloud"
git branch -M main
git remote add origin https://github.com/你的用户名/仓库名.git
git push -u origin main
```

### 3.3 配置 Secret（必填）

仓库 → **Settings → Secrets and variables → Actions** → New repository secret：

| Name | 值 |
|------|-----|
| `UNIKRAFT_API_TOKEN` | Unikraft API Token（整串粘贴） |

### 3.4 可选 Variables

同页 **Variables** 标签：

| 变量 | 默认 | 说明 |
|------|------|------|
| `PROJECT_NAME` | `nezha` | 实例/服务/镜像名，同名即更新 |
| `DEPLOY_REGIONS` | `sin` | 地区：`sin` / `fra` / `dal` / `sfo` / `was` |
| `MEMORY_MB` | `512` | 内存；节点很多可调 `1024` |
| `DATA_VOLUME` | `nezha-data` | 卷名前缀（实际为 `nezha-data-sin`） |
| `VOLUME_MB` | `1024` | 卷大小（MB） |

---

## 4. 首次部署（逐步）

### 步骤 1：打开 Actions

GitHub 仓库页 → **Actions** → 选中左侧：

**Deploy Nezha to Unikraft Cloud**

### 步骤 2：Run workflow

点击 **Run workflow**，按需填写：

| 表单项 | 建议 |
|--------|------|
| 项目名 | `nezha`（或自定义，小写字母数字和 `-`） |
| 地区 | 离你/用户近的，如 `sin - 新加坡` |
| 内存 | `512` 起步 |
| 镜像 tag | `latest`；生产可锁版本如具体 tag |
| 用户前端 | **Aurora 主题**（推荐）或 **官方默认前端** |

### 步骤 3：等待完成

一般 3–10 分钟，流程为：

```text
checkout
→（若选 Aurora）npm 构建 theme/
→ 从 ghcr.io 拉 nezhahq/nezha 层做 rootfs
→ 注入 user-dist + 生成 start.sh（含空卷初始化 config）
→ unikraft build 推送到你的 org 仓库
→ 创建 service（443→8008）+ volume + 启动实例
```

日志末尾应出现：

```text
===== 部署完成 =====
sin  running  https://xxxxxxxx.sin.unikraft.app
```

复制该 HTTPS 地址。

### 步骤 4：验证

浏览器打开：

1. 根路径：应看到状态页（尚无 Agent 时可能为空/演示感正常）
2. `/dashboard`：应出现登录页

若根路径或后台都无法打开，见 [故障排查](#11-故障排查)。

---

## 5. 首次登录与面板配置

1. 访问 `https://你的FQDN/dashboard`
2. 用户名/密码：`admin` / `admin`
3. 右上角头像 → **更新个人信息** → 设置**强密码**
4. 进入 **系统设置**（或「设置」）：
   - **站点名称**：随意
   - **语言**：简体中文等
   - **Agent 对接地址 / install_host**：填  
     `你的FQDN` 或 `你的自定义域名`  
     **不要**写 `https://`，**不要**写路径  
     示例：`xxxxxxxx.sin.unikraft.app`
   - **使用 TLS**：勾选 / 开启（UKC 对外是 443 HTTPS）
5. 保存后到 **服务器** 页面生成安装命令

> 对接地址填错是 Agent 不上线的最常见原因。

---

## 6. 安装 Agent（被控端）

在需要被监控的机器上执行面板生成的安装命令。关键环境变量含义：

```text
NZ_SERVER=xxxxxxxx.sin.unikraft.app:443
NZ_TLS=true
NZ_CLIENT_SECRET=面板里的通信密钥
```

注意：

- 端口用 **443**（不是 8008；8008 只在 UKC 容器内部）
- **TLS = true**
- 防火墙放行该机器访问公网 443

装好后回到面板「服务器」列表，应显示在线。

---

## 7. 自定义域名

### 方式 A：UKC 原生绑定（推荐）

**1）DNS**

```text
类型: CNAME
主机: status（或 @ / www，视域名商而定）
目标: xxxxxxxx.sin.unikraft.app
```

若域名在 Cloudflare：该记录建议 **仅 DNS（灰云）**，先不要橙色代理。

**2）把域名登记到 Service**

本机安装 [unikraft CLI](https://github.com/unikraft-cloud/cli)，用同一 Token 登录后：

```bash
export UNIKRAFT_API_TOKEN='你的token'
# 登录方式与 CI 中 scripts 相同，或按官方文档 login

unikraft services list
unikraft instances list

# 服务名一般是：项目名-地区，例如 nezha-sin
unikraft services edit nezha-sin \
  --domains xxxxxxxx.sin.unikraft.app \
  --domains status.example.com
```

**只配 CNAME、不执行 `services edit`，会看到：**

```text
There is no service on this URL.
```

这是平台明确提示：流量到了 UKC，但没有任何 Service 声明该 Host。

### 方式 B：Cloudflare Worker 反代

```js
export default {
  async fetch(req) {
    const url = new URL(req.url);
    url.hostname = "xxxxxxxx.sin.unikraft.app"; // 改成你的 FQDN
    return fetch(new Request(url, req));
  },
};
```

Worker 绑定自定义域即可。换后端只改一行 hostname。

绑定自定义域后，把面板里的 **Agent 对接地址** 改成新域名，并保证 TLS 开启。

---

## 8. 更新 / 回滚 / 删除

### 更新面板或主题

- 修改 `theme/` 后 push，再跑一次 **Deploy** workflow  
- 或仅换 `image_tag` 再部署  
- **同名项目**：先删旧实例再创建（中断约几十秒），**Volume 数据保留**

### 只要官方前端、不要 Aurora

Run workflow 时「用户前端」选 **官方默认前端**（`plain` 模式，不跑 npm）。

### 删除

Actions → **Destroy** → `target` 填项目名（如 `nezha`）或 `all`，再填 `DELETE` 确认。  
会删除对应实例 / service / 镜像；Volume 是否一并删除以 destroy 脚本逻辑为准，重要数据请先自行备份。

### 备份数据（可选）

UKC 无 Fly 那种 `fly ssh sftp`。需要备份时：

- 在面板侧导出（若版本支持），或  
- 部署前在可 SSH 的环境用官方镜像跑一份，把 `/dashboard/data` 拷出后，再考虑迁移策略  

生产环境建议定期在面板外保留配置与数据库副本。

---

## 9. 与 Fly.io 方案对照

| 项目 | nezha-fly（Fly.io） | 本仓库（Unikraft Cloud） |
|------|---------------------|---------------------------|
| 基础镜像 | `ghcr.io/nezhahq/nezha` | 相同 |
| 数据目录 | Volume → `/dashboard/data` | 相同 |
| 内部端口 | 8008 | 相同 |
| 对外 HTTPS | Fly 边缘 | UKC 边缘 `443→8008/tls+http` |
| 空卷初始化 config | `run.sh` 拷贝默认配置 | `start.sh` 内同样逻辑 |
| 用户前端 | 官方默认 | 可选 **Aurora** 或官方 |
| 部署触发 | Fly token + `fly deploy` | UKC token + GitHub Actions |
| 地区 | Fly region（如 sin） | UKC metro：sin/fra/dal/sfo/was |
| SSH 进容器 | Fly 支持 | UKC 基本不提供传统 SSH |

思路一致：**官方镜像 + 持久化 data 目录**；本仓库额外把 Aurora 打进镜像，并改成 UKC 流水线。

---

## 10. 目录结构

```text
nezha-ukc/
├── .github/workflows/
│   ├── deploy.yml              # 一键部署（可选 Aurora）
│   └── destroy.yml             # 清理资源
├── scripts/
│   ├── build-nezha-aurora.sh   # 拉官方镜像 ± 注入主题 → push
│   ├── deploy.sh               # 创建 service / volume / 启动
│   ├── anyimage.sh             # 通用 Docker 镜像导入（备用）
│   └── pull-base.py            # 拉 OCI 层为 rootfs
├── theme/                      # nezha-aurora 源码
│   ├── src/
│   ├── package.json
│   └── ...
└── README.md                   # 本教程
```

### CI 构建链路

```text
[可选] npm run build → theme/dist/*
拉取 ghcr.io/nezhahq/nezha → _img/rootfs/
[可选] dist → _img/rootfs/dashboard/user-dist/
生成 start.sh（ENV + 初始化 config + exec 原入口）
unikraft build → $ORG/$PROJECT_NAME:latest
deploy.sh：
  services create  443:8008/tls+http
  volumes create   挂到 /dashboard/data
  unikraft run     scale-to-zero=off
```

---

## 11. 故障排查

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| Actions 立刻失败缺 token | 未配 Secret | 检查 `UNIKRAFT_API_TOKEN` |
| npm / 主题构建失败 | 网络或 lock | 看日志；可改为「官方默认前端」先上线 |
| 拉镜像失败 | ghcr 网络 | 脚本已尝试 mirror；重跑 Deploy |
| `No image` 启动失败 | 镜像同步延迟 | 脚本已重试；仍失败再跑一次 |
| 打开域名 “There is no service on this URL” | 未 `services edit` 绑定域名 | 见第 7 节 |
| `/dashboard` 能开、根路径异常 | 主题注入失败或选了 plain | 看 build 日志是否「已注入 Aurora」 |
| Agent 不上线 | 对接地址/TLS/端口错误 | 地址无协议；端口 443；TLS true |
| 登录后数据全空（重部署后） | 换了地区或卷名 | 数据在对应 `nezha-data-地区` 卷上 |
| 注册表 403 超额 | 镜像层占满约 1GiB 配额 | 控制台删无引用旧镜像 |
| WebSocket 断线 | 反代/CDN 未升级 WS | 官方域名一般正常；自建反代需支持 Upgrade |

本地排查 CLI 示例：

```bash
export UNIKRAFT_API_TOKEN='...'
# 按官方方式 login 后：
unikraft instances list
unikraft services list
unikraft instances logs nezha
```

---

## 12. 安全建议

1. **立刻修改** 默认 `admin` 密码。  
2. 仓库建议 Private；Token 只放在 Secrets。  
3. 自定义域名优先原生绑定；Cloudflare 代理时注意真实 IP（面板可配相关头）。  
4. 不要把 API Token、面板密码写进代码或公开 Issue。  
5. Agent 密钥视为敏感信息，不要提交到 Git。

---

## 13. 限制说明

1. **不是 VPS**：不能在实例里再跑 Docker、不能装任意系统服务。  
2. **Agent 协议**：依赖 UKC 边缘对 HTTP/HTTPS（及可能的 h2）转发；绝大多数场景可用，不保证与 Fly 的 `h2_backend` 行为 100% 一致。  
3. **多地区**：每个地区独立实例 + 独立卷，监控数据不自动同步。  
4. **备份**：请自行定期备份重要配置；不要把 UKC 当作唯一数据副本。  
5. **Aurora 单独部署**：仅主题无法监控服务器；必须配合哪吒后端（本仓库已打包在一起）。

---

## 快速检查清单

- [ ] 已添加 `UNIKRAFT_API_TOKEN`
- [ ] Actions 部署成功并复制了 `https://….unikraft.app`
- [ ] `/dashboard` 可登录并已改密码
- [ ] 系统设置中 Agent 地址为 FQDN、TLS 开启
- [ ] 至少一台机器 Agent 显示在线
- [ ] （可选）自定义域名已 CNAME + `services edit`

完成以上即表示部署可用。若某一步日志报错，把 **失败步骤的完整日志片段** 保留以便继续排查。

---

## 许可

- 整合脚本与本说明：按仓库使用。  
- 哪吒 Dashboard：遵循 [nezhahq/nezha](https://github.com/nezhahq/nezha) 上游许可。  
- Aurora：见 `theme/LICENSE`。  
- nezha-fly 仅作部署思路参考，本仓库不依赖 Fly 平台。
