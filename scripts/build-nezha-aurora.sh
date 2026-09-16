#!/usr/bin/env bash
# 导入官方哪吒镜像 →（可选）注入 Aurora 主题 → 推送到 UKC 镜像仓库
# 用法:
#   bash scripts/build-nezha-aurora.sh [镜像tag] [实例名] [with-aurora|plain]
# 例:
#   bash scripts/build-nezha-aurora.sh latest nezha with-aurora
#   bash scripts/build-nezha-aurora.sh latest nezha plain
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE_TAG="${1:-latest}"
NAME="${2:-nezha}"
MODE="${3:-with-aurora}"   # with-aurora | plain
NEZHA_REF="ghcr.io/nezhahq/nezha:${IMAGE_TAG}"

TOKEN="${UNIKRAFT_API_TOKEN:?缺少 UNIKRAFT_API_TOKEN}"
ORG=$(printf '%s' "$TOKEN" | base64 -d | cut -d: -f1 | sed -e 's/^robot\$//' -e 's/\.users\.kraftcloud$//')
[ -n "$ORG" ] || { echo "无法从 token 解析组织名"; exit 1; }

echo "模式: $MODE | 镜像: $NEZHA_REF | 实例名: $NAME | org: $ORG"

# ---------- 1) 可选：构建 Aurora ----------
if [ "$MODE" = "with-aurora" ]; then
  echo "===== 1/4 构建 Aurora 主题 ====="
  [ -d theme ] || { echo "缺少 theme/ 目录"; exit 1; }
  command -v npm >/dev/null 2>&1 || { echo "需要 npm"; exit 1; }
  (
    cd theme
    if [ -f package-lock.json ]; then
      npm ci --no-audit --no-fund || npm install --no-audit --no-fund
    else
      npm install --no-audit --no-fund
    fi
    npm run build
    test -f dist/index.html || { echo "构建失败：没有 dist/index.html"; exit 1; }
    echo "主题产物: $(find dist -type f | wc -l) 个文件"
  )
else
  echo "===== 1/4 跳过主题（纯官方前端）====="
fi

# ---------- 2) 拉取官方镜像 rootfs ----------
echo "===== 2/4 拉取哪吒官方镜像 rootfs ====="
REF="$NEZHA_REF"
case "$REF" in
  ghcr.io/*)   REG="https://ghcr.io";              REPO="${REF#ghcr.io/}" ;;
  docker.io/*) REG="https://registry-1.docker.io"; REPO="${REF#docker.io/}" ;;
  *)           REG="https://registry-1.docker.io"; REPO="$REF" ;;
esac
case "$REPO" in
  */*) ;;
  *)   REPO="library/$REPO" ;;
esac
if [[ "$REPO" == *:* ]]; then TAG="${REPO##*:}"; REPO="${REPO%:*}"; else TAG="latest"; fi

rm -rf _img
mkdir -p _img
OUT=$(python3 scripts/pull-base.py "$REPO" "$TAG" _img/rootfs "$REG" || \
      python3 scripts/pull-base.py "$REPO" "$TAG" _img/rootfs "https://mirror.gcr.io")
echo "$OUT" | tail -5
CFG_LINE=$(echo "$OUT" | grep '^IMAGE_CONFIG=' || true)
[ -n "$CFG_LINE" ] || { echo "镜像没有 config（无法确定启动命令）"; exit 1; }
CFG="${CFG_LINE#IMAGE_CONFIG=}"

# ---------- 3) 注入主题 + 生成启动脚本 ----------
echo "===== 3/4 准备 rootfs / 启动脚本 ====="
if [ "$MODE" = "with-aurora" ]; then
  # 哪吒：本地 user-dist 优先于内嵌官方用户前端
  mkdir -p _img/rootfs/dashboard/user-dist
  cp -a theme/dist/. _img/rootfs/dashboard/user-dist/
  test -f _img/rootfs/dashboard/user-dist/index.html
  echo "已注入 Aurora: $(find _img/rootfs/dashboard/user-dist -type f | wc -l) 个文件 → /dashboard/user-dist"
fi

# 生成 start.sh（含 nezha-fly 式 config 初始化）
python3 - "$CFG" > _img/rootfs/start.sh <<'PY'
import json, shlex, sys
c = json.loads(sys.argv[1])
print("#!/bin/sh")
print("set -e")
for e in c["env"]:
    if "=" in e:
        k, _, v = e.partition("=")
        print("export %s=%s" % (k, shlex.quote(v)))
if not any(e.startswith("PATH=") for e in c["env"]):
    print('export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"')
print("mkdir -p /dashboard/data")
print('if [ ! -f /dashboard/data/config.yaml ]; then')
print('  if [ -f /dashboard/config.yaml ]; then')
print('    echo "[nezha-ukc] 初始化默认 config.yaml → /dashboard/data/"')
print("    cp /dashboard/config.yaml /dashboard/data/config.yaml")
print("  fi")
print("fi")
wd = c["working_dir"] or "/"
print("cd %s 2>/dev/null || cd /" % shlex.quote(wd))
argv = list(c.get("entrypoint") or []) + list(c.get("cmd") or [])
if not argv:
    argv = ["/dashboard/app"]
print("exec " + " ".join(shlex.quote(a) for a in argv))
PY
chmod 755 _img/rootfs/start.sh
echo "--- start.sh ---"
cat _img/rootfs/start.sh

cat > _img/Kraftfile <<EOF
spec: v0.7
runtime: base-compat:latest
rootfs:
  source: ./rootfs
  format: erofs
cmd: ["/bin/sh", "/start.sh"]
EOF

# ---------- 4) 构建推送 ----------
echo "===== 4/4 构建并推送 $ORG/$NAME:latest ====="
printf '%s' "$TOKEN" | unikraft login --token=- --organization "$ORG" >/dev/null
unikraft build _img --output "$ORG/$NAME:latest"
echo ""
echo "完成: $ORG/$NAME:latest"
echo "部署: PROJECT_NAME=$NAME APP_PORT=8008 DATA_VOLUME=nezha-data DATA_MOUNT_PATH=/dashboard/data \\"
echo "      MEMORY_MB=512 REGIONS=sin bash scripts/deploy.sh deploy"
