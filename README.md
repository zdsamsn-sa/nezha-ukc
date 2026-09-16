# 哪吒监控 V2 + Aurora 主题 → Unikraft Cloud 一键部署

把官方 **哪吒 Dashboard**（`ghcr.io/nezhahq/nezha`）部署到 Unikraft Cloud，并内置 **Nezha Aurora** 现代用户前端主题。

| 组件 | 说明 |
|------|------|
| 面板本体 | 官方镜像 `ghcr.io/nezhahq/nezha`（HTTP 8008，Agent 同端口 gRPC/h2c） |
| 用户前端 | [Nezha Aurora](https://github.com/) 主题，挂载到 `/dashboard/user-dist` 覆盖官方前台 |
| 数据持久化 | UKC Volume → `/dashboard/data`，重部署不丢服务器/告警配置 |
| 触发方式 | GitHub Actions **手动** Run workflow（push 不自动部署） |

> **说明**：你提供的 `nezha-aurora-main.zip` 是**纯前端主题**，不能单独当监控面板用。本仓库已把它与官方 Dashboard 打成一个可运行的 UKC 实例。

---

## 一、架构与限制（必读）

### Unikraft Cloud 是什么

- 跑的是 **unikernel 实例**，不是完整 Linux VPS。
- 适合「一个进程 + 监听端口」；没有 systemd / Docker-in-Docker / 任意装包。
- 对外：`443` TLS 终止 → 转到容器内 `APP_PORT`（本方案为 `8008`）。

### 哪吒在 UKC 上能做什么

| 能力 | 支持情况 |
|------|----------|
| Web 面板 / Aurora 主题 | ✅ |
| 管理后台 `/dashboard` | ✅（默认账号见下文） |
| 数据持久化 | ✅ Volume 挂载 `/dashboard/data` |
| Agent 上报 | ⚠️ 通常可用（Agent 指向 `域名:443` 且开启 TLS）；个别网络/协议环境需自测 |
| 多地区同数据 | ❌ 每个地区独立 Volume，数据不互通 |

### 推荐用法

1. **面板放 UKC 一个地区**（如 `sin`）。
2. 各服务器上装 **Agent**，对接地址填 UKC 官方域名或你的自定义域名（443 + TLS）。
3. 需要好看的状态页 → 已内置 Aurora，打开根路径即可。

---

## 二、首次配置（约 5 分钟）

### 1. 建仓库

解压本包，推到 GitHub（建议 **Private**）：

```bash
cd nezha-ukc
git init
git add .
git commit -m "Nezha + Aurora for Unikraft Cloud"
git branch -M main
git remote add origin https://github.com/你的用户名/你的仓库.git
git push -u origin main
```

### 2. 添加 Secret（必填）

仓库 → **Settings → Secrets and variables → Actions → New repository secret**

| Name | Value |
|------|--------|
| `UNIKRAFT_API_TOKEN` | Unikraft 控制台 → Settings → API Keys |

### 3. 可选 Variables

| 变量 | 默认 | 说明 |
|------|------|------|
| `DEPLOY_REGIONS` | `sin` | 地区代码，逗号分隔：`fra,sin,dal,sfo,was` |
| `PROJECT_NAME` | `nezha` | 项目名（同名=更新） |
| `MEMORY_MB` | `512` | 内存；节点多可调到 `1024` |
| `DATA_VOLUME` | `nezha-data` | 卷名前缀（实际为 `nezha-data-sin` 等） |
| `VOLUME_MB` | `1024` | 卷大小 MB |

---

## 三、部署步骤

1. 打开 GitHub 仓库 → **Actions**
2. 选择 **Deploy Nezha + Aurora to Unikraft Cloud**
3. **Run workflow**，可改：
   - 项目名（默认 `nezha`）
   - 地区（默认新加坡）
   - 内存（默认 512）
   - 镜像 tag（默认 `latest`，可锁如 `v1.0.0`）
4. 等待约 3–8 分钟（拉镜像 + 构建主题 + 推送 + 启动）

成功日志末尾类似：

```text
===== 部署完成 =====
sin  running  https://xxxx.sin.unikraft.app
```

### 访问

| 入口 | URL |
|------|-----|
| 用户前台（Aurora） | `https://xxxx.sin.unikraft.app/` |
| 管理后台 | `https://xxxx.sin.unikraft.app/dashboard` |

**默认账号**：`admin` / `admin`（**登录后立刻改密码**）

---

## 四、首次进入面板必做

1. 打开 `/dashboard`，用 `admin`/`admin` 登录。
2. 右上角头像 → **更新个人信息** → 改强密码。
3. **系统设置**：
   - 站点名称、语言
   - **Agent 对接地址**：填 `你的域名` 或 `xxxx.sin.unikraft.app`（不要带 `https://`）
   - 勾选 **使用 TLS 连接**（UKC 对外是 443 HTTPS）
4. **服务器** → 生成安装命令，到各机器执行 Agent 安装脚本。

Agent 示例环境变量含义：

```text
NZ_SERVER=xxxx.sin.unikraft.app:443
NZ_TLS=true
NZ_CLIENT_SECRET=面板里生成的密钥
```

---

## 五、自定义域名（可选）

### 方式 A：UKC 原生绑定

1. DNS 添加 CNAME：

```text
status.example.com  →  xxxx.sin.unikraft.app
```

（Cloudflare 建议该记录 **仅 DNS / 灰云**，避免橙色代理干扰 Host。）

2. 本地 CLI 绑定（需已登录 unikraft）：

```bash
unikraft services list
unikraft services edit nezha-sin \
  --domains xxxx.sin.unikraft.app \
  --domains status.example.com
```

若只写 CNAME、不 `services edit`，浏览器会看到：

```text
There is no service on this URL.
```

### 方式 B：Cloudflare Worker 反代

```js
export default {
  async fetch(req) {
    const url = new URL(req.url);
    url.hostname = "xxxx.sin.unikraft.app"; // 换成你的 FQDN
    return fetch(new Request(url, req));
  },
};
```

绑定自定义域即可。WebSocket 一般可走通。

---

## 六、更新与删除

### 更新面板 / 主题

- 改代码或想换镜像 tag → 再跑一次 **Deploy** workflow。
- **同名项目会先删实例再创建**（中断约几十秒），**Volume 数据保留**。
- 主题源在仓库 `theme/`，改完 push 再部署即可生效。

### 删除资源

Actions → **Destroy** → `target` 填 `nezha`（或你的项目名）或 `all`，再填 `DELETE` 确认。

---

## 七、目录结构

```text
nezha-ukc/
├── .github/workflows/
│   ├── deploy.yml          # 构建哪吒+Aurora 并部署
│   └── destroy.yml         # 清理
├── scripts/
│   ├── build-nezha-aurora.sh   # 拉官方镜像 + 注入主题 + push
│   ├── deploy.sh               # 创建 service / volume / 启动实例
│   ├── anyimage.sh             # 通用 Docker 镜像导入（备用）
│   └── pull-base.py            # 拉 OCI 层做 rootfs
├── theme/                      # Aurora 主题源码（构建产物注入镜像）
│   ├── src/
│   ├── package.json
│   └── ...
└── README.md
```

### 构建链路（CI 内）

```text
npm run build (theme/)
    → theme/dist/*
拉取 ghcr.io/nezhahq/nezha
    → _img/rootfs/
复制 dist → _img/rootfs/dashboard/user-dist/
unikraft build → ORG/nezha:latest
unikraft run（挂卷 /dashboard/data，端口 8008）
```

---

## 八、可用地区

| 代码 | 地区 |
|------|------|
| `sin` | 新加坡 |
| `fra` | 法兰克福 |
| `dal` | 达拉斯 |
| `sfo` | 旧金山 |
| `was` | 华盛顿 |

---

## 九、故障排查

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| Actions 失败：缺 token | 未配 `UNIKRAFT_API_TOKEN` | 检查 Secrets |
| 构建失败：npm | 网络/锁文件 | 看日志；可删 `theme/package-lock.json` 再 push |
| 实例启动失败 No image | 镜像同步延迟 | 脚本已重试 5 次；仍失败再跑一次 Deploy |
| 打开域名 “There is no service on this URL” | 只配了 CNAME，未绑 service | 见第五节 `services edit` |
| 前台空白 / API 401 | 面板开了强制登录 | 后台关闭 force_auth，或访客可访问公开 API |
| Agent 不上线 | 对接地址/TLS 不对 | 地址不要带协议；端口 443；TLS=true |
| 注册表 403 超额 | 镜像层占满约 1GiB 配额 | 控制台删除无引用的旧镜像 |
| 重部署后主题变回官方 | 旧镜像被缓存或注入失败 | 看 build 日志是否有「已注入」；强制重跑 Deploy |

本地验证 CLI（可选）：

```bash
export UNIKRAFT_API_TOKEN=你的token
unikraft login --token=- --organization <从token解析的org>
unikraft instances list
unikraft services list
unikraft instances logs nezha
```

---

## 十、安全建议

1. **立刻修改** 默认 `admin` 密码。
2. 仓库建议 Private；token 只放 Secrets。
3. 自定义域名优先 UKC 原生绑定；Cloudflare 代理时注意真实 IP 头（哪吒后台可配）。
4. 不要把 `UNIKRAFT_API_TOKEN`、面板密码写进代码或公开 Issue。

---

## 十一、与「仅主题 / 仅面板」的区别

| 方案 | 结果 |
|------|------|
| 只部署 Aurora 静态站 | 无后端，API 全失败（除非再反代到已有哪吒） |
| 只部署官方哪吒镜像 | 可用，但是官方默认前台 |
| **本仓库（哪吒 + Aurora）** | 完整面板 + 现代状态页，适合 UKC 一键 |

若你已有哪吒面板、只想换皮：在已有 Docker 上把 `theme/dist` 挂到 `/dashboard/user-dist` 即可，不必上 UKC。

---

## 十二、许可证

- 部署脚本与整合方式：按本仓库说明使用。
- 哪吒 Dashboard：遵循 [nezhahq/nezha](https://github.com/nezhahq/nezha) 上游许可。
- Aurora 主题：见 `theme/LICENSE`（上游包内说明）。
