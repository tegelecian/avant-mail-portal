#!/usr/bin/env bash
# One-shot install of the Avant Mail Portal on a fresh Ubuntu 24.04 VPS.
# Run as root:   DOMAIN=mail.example.com bash setup.sh
# Idempotent — safe to re-run after a git pull.
set -euo pipefail

: "${DOMAIN:?Set DOMAIN=your.hostname (DNS A record must already point here)}"
REPO="${REPO:-https://github.com/tegelecian/avant-mail-portal.git}"
APP_DIR=/opt/portal
APP_USER=portal

echo "==> packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q python3 python3-venv python3-pip git ufw curl \
    debian-keyring debian-archive-keyring apt-transport-https
if ! command -v caddy >/dev/null; then
  curl -1sLf 'https://dl.cloudflare.com/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudflare.com/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -q && apt-get install -y -q caddy
fi

echo "==> user + code"
id -u $APP_USER >/dev/null 2>&1 || useradd --system --home $APP_DIR --shell /usr/sbin/nologin $APP_USER
if [ -d $APP_DIR/.git ]; then
  git -C $APP_DIR pull --ff-only
else
  git clone "$REPO" $APP_DIR
fi
mkdir -p $APP_DIR/data/attachments $APP_DIR/data/backups
[ -f $APP_DIR/.env ] || { cp $APP_DIR/deploy/env.server.example $APP_DIR/.env; echo "!! wrote $APP_DIR/.env from template — FILL IT IN"; }
chmod 600 $APP_DIR/.env

echo "==> python venv"
[ -d $APP_DIR/.venv ] || python3 -m venv $APP_DIR/.venv
$APP_DIR/.venv/bin/pip install -q --upgrade pip
$APP_DIR/.venv/bin/pip install -q -r $APP_DIR/requirements.txt
chown -R $APP_USER:$APP_USER $APP_DIR

echo "==> systemd"
cp $APP_DIR/deploy/portal.service /etc/systemd/system/portal.service
systemctl daemon-reload
systemctl enable portal
systemctl restart portal

echo "==> caddy (automatic HTTPS for $DOMAIN)"
sed "s/__DOMAIN__/$DOMAIN/" $APP_DIR/deploy/Caddyfile > /etc/caddy/Caddyfile
systemctl enable caddy
systemctl reload caddy || systemctl restart caddy

echo "==> firewall"
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null

echo "==> unattended security updates"
apt-get install -y -q unattended-upgrades >/dev/null
dpkg-reconfigure -f noninteractive unattended-upgrades

sleep 2
echo "==> health: $(curl -s -m 10 http://127.0.0.1:8080/healthz || echo 'NOT RESPONDING')"
echo "Done. Site: https://$DOMAIN   Logs: journalctl -u portal -f"
