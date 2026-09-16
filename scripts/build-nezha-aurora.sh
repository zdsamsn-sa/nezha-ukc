#!/usr/bin/env bash
# 构建 Aurora 主题 + 导入官方哪吒镜像 + 注入 user-dist → 推送到 UKC 镜像仓库
# 用法: bash scripts/build-nezha-aurora.sh [镜像tag] [实例名]
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE_TAG="${1:-latest}"
NAME="${2:-nezha}"
NEZHA_REF="ghcr.io/nezhahq/nezha:${IMAGE_TAG}"

TOKEN="${UNIKRAFT_API_TOKEN:?缺少 UNIKRAFT_API_TOKEN}"
ORG=$(printf '%s' "$TOKEN" | base64 -d | cut -d: -f1 | sed -e 's/^robot\$//' -e 's/\.users\.kraftcloud$//')

echo "===== 1/4 构建 Aurora 主题 ====="
if [ ! -d theme ]; then
  echo "缺少 theme/ 目录"; exit 1
fi
(
  cd theme
  # CI 上 Node 通常已有；本地没有则提示
  if ! command -v npm >/dev/null 2>&1; then
    echo "需要 npm 才能构建主题"; exit 1
  fi
  npm ci --no-audit --no-fund 2>/dev/null || npm install --no-audit --no-fund
  npm run build
  test -f dist/index.html || { echo "构建失败：没有 dist/index.html"; exit 1; }
  echo "主题产物: $(find dist -type f | wc -l) 个文件"
)

echo "===== 2/4 拉取哪吒官方镜像 rootfs ====="
# 复用 anyimage 的拉镜像逻辑，但先不要 build，以便注入主题
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
OUT=$(python3 scripts/pull-base.py "$REPO" "$TAG" _img/rootfs "$REG")
echo "$OUT" | tail -3
CFG_LINE=$(echo "$OUT" | grep '^IMAGE_CONFIG=' || true)
[ -n "$CFG_LINE" ] || { echo "镜像没有 config"; exit 1; }
CFG="${CFG_LINE#IMAGE_CONFIG=}"

echo "===== 3/4 注入 Aurora 到 /dashboard/user-dist ====="
# 哪吒 V2：本地 user-dist 优先于内嵌官方前端
mkdir -p _img/rootfs/dashboard/user-dist
# dist 内文件直接放到 user-dist 根（不要再套一层 dist/）
cp -a theme/dist/. _img/rootfs/dashboard/user-dist/
# 确认关键文件存在
test -f _img/rootfs/dashboard/user-dist/index.html
echo "已注入: $(find _img/rootfs/dashboard/user-dist -type f | wc -l) 个主题文件"

# 生成 start.sh（与 anyimage.sh 一致）
python3 - "$CFG" > _img/rootfs/start.sh <<'PY'
import json, shlex, sys
c = json.loads(sys.argv[1])
print("#!/bin/sh")
for e in c["env"]:
    if "=" in e:
        k, _, v = e.partition("=")
        print("export %s=%s" % (k, shlex.quote(v)))
if not any(e.startswith("PATH=") for e in c["env"]):
    print('export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"')
wd = c["working_dir"]
print('cd %s 2>/dev/null || cd /' % shlex.quote(wd))
argv = c["entrypoint"] + c["cmd"]
if not argv:
    sys.exit("镜像没有 ENTRYPOINT/CMD")
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

echo "===== 4/4 构建并推送镜像 $ORG/$NAME:latest ====="
# 登录
printf '%s' "$TOKEN" | unikraft login --token=- --organization "$ORG" >/dev/null
unikraft build _img --output "$ORG/$NAME:latest"
echo "完成: $ORG/$NAME:latest"
echo "下一步: PROJECT_NAME=$NAME APP_PORT=8008 DATA_VOLUME=nezha-data DATA_MOUNT_PATH=/dashboard/data bash scripts/deploy.sh deploy"
