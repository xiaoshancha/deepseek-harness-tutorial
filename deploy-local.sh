#!/usr/bin/env bash
# ============================================================
# 一键部署：构建 → 上传到服务器中转目录 → sudo 安装到网站目录
#
# 关键前提（务必了解）：
#   1) 阿里云 ECS 只能用 admin 用户 SSH（root 禁登录），密钥 id_ed25519_penguin
#   2) 网站目录属主是 www-data，admin 对其“无写权限”，不能直接 scp 进去
#   3) admin 有免密 sudo → 所以走「先传到 /tmp 中转，再 sudo cp 安装」两步
#
# 用法：bash deploy-local.sh
# ============================================================
set -euo pipefail

# ===== 配置（按需修改）=====
HOST="123.56.2.125"
USER="admin"
PORT="22"
KEY="$HOME/.ssh/id_ed25519_penguin"

SITE_ROOT="/www/wwwroot/tutorial.baimuyuan.online"          # Nginx 的 root
TUTORIAL_DIR="$SITE_ROOT/deepseek-harness-tutorial"         # 教程站（VitePress 产物）
STAGE="/tmp/dsh-deploy"                                     # 服务器中转目录
DOMAIN="https://tutorial.baimuyuan.online"
# ==========================

# npm 兼容：Windows Git Bash 下 npm 可能是 npm.cmd
NPM="npm"
command -v npm >/dev/null 2>&1 || NPM="npm.cmd"

SSH_OPTS="-i $KEY -p $PORT -o StrictHostKeyChecking=no -o ConnectTimeout=20"
SSH="ssh $SSH_OPTS $USER@$HOST"
SCP="scp -i $KEY -P $PORT -o StrictHostKeyChecking=no"

echo "[1/4] 构建静态站 ..."
$NPM run build

echo "[2/4] 上传到中转目录 $STAGE ..."
$SSH "find '$STAGE' -mindepth 1 -delete 2>/dev/null || true; mkdir -p '$STAGE/dist'"
$SCP -r .vitepress/dist/* "$USER@$HOST:$STAGE/dist/"
$SCP home/index.html "$USER@$HOST:$STAGE/home-index.html"

echo "[3/4] sudo 安装到网站目录 ..."
$SSH "set -e
  sudo mkdir -p '$TUTORIAL_DIR'
  sudo find '$TUTORIAL_DIR' -mindepth 1 -delete
  sudo cp -rf '$STAGE/dist'/. '$TUTORIAL_DIR'/
  sudo cp -f '$STAGE/home-index.html' '$SITE_ROOT/index.html'
  sudo chown -R www-data:www-data '$TUTORIAL_DIR' '$SITE_ROOT/index.html'
"

echo "[4/4] 公网校验 ..."
curl -sS -o /dev/null -w "  首页  %{http_code}\n" "$DOMAIN/"
curl -sS -o /dev/null -w "  教程  %{http_code}\n" "$DOMAIN/deepseek-harness-tutorial/"
echo "完成 ✅  打开 $DOMAIN/"
