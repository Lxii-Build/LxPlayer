#!/bin/sh
# 在部署服务器上执行：起 LxPlayer 后端容器（宿主机 10044 -> 容器 10044）
set -e

APP_DIR=/opt/lxplayer-server
DATA_DIR=$APP_DIR/data

# 1) 数据目录：容器以 nobody(65534) 运行，宿主目录必须同 uid 才可写
mkdir -p "$DATA_DIR"
chown 65534:65534 "$DATA_DIR"

# 2) 生成密钥（仅首次生成；已存在则复用，避免重建容器后令牌/口令变化）
CRED=$APP_DIR/credentials.env
if [ ! -f "$CRED" ]; then
  JWT=$(openssl rand -hex 32)
  ADMIN=$(openssl rand -hex 12)
  umask 077
  cat > "$CRED" <<EOF
JWT_SECRET=$JWT
ADMIN_PASSWORD=$ADMIN
EOF
fi
. "$CRED"

# 3) 起容器（同名的先删）
docker rm -f lxplayer-server >/dev/null 2>&1 || true
docker run -d \
  --name lxplayer-server \
  --restart unless-stopped \
  -p 10044:10044 \
  -e JWT_SECRET="$JWT_SECRET" \
  -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  -e DB_PATH=/data/lxplayer.db \
  -v "$DATA_DIR":/data \
  lxplayer-server:latest >/dev/null

# 4) 验证
echo "=== docker ps ==="
docker ps --filter name=lxplayer-server --format '{{.Names}}  {{.Status}}  {{.Ports}}'
echo "=== health ==="
i=0
while [ $i -lt 10 ]; do
  OUT=$(curl -s -m 5 http://127.0.0.1:10044/api/v1/health || true)
  if [ -n "$OUT" ]; then echo "$OUT"; break; fi
  i=$((i+1)); sleep 1
done
[ -n "$OUT" ] || { echo "HEALTH FAILED - container logs:"; docker logs --tail 30 lxplayer-server; exit 1; }
echo
echo "=== admin login smoke (expect 200 + token) ==="
curl -s -m 5 -o /dev/null -w 'admin_login_http=%{http_code}\n' \
  -X POST http://127.0.0.1:10044/admin/api/v1/login \
  -H 'Content-Type: application/json' \
  -d "{\"password\":\"$ADMIN_PASSWORD\"}"
echo
echo "=== credentials (管理员口令) ==="
echo "ADMIN_PASSWORD=$ADMIN_PASSWORD"
