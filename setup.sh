#!/bin/env sh
#
# Usage: ./setup.sh [desired-ubuntu-password]
#
# Then login with:
#     user: ubuntu
#     password: rx-myyyymmdd (e.g. rx-m20260127) --or-- 
#               <password provided on cli>
#
# This script installs wetty as a daemon listenting on port 443 with a self
# signed cert on a new (untampered with) standard RX-M Ubuntu lab system. To
# connect to the system browse to: https://<ip-of-lab-vm>/wetty
#
# This is a fast websocket based terminal solution for those who cannot use
# ssh. Note that installing wetty does not disable standard ssh/key based
# login support.
#
# Caveats:
# ==============================================
# 1. While the connection is TLS it uses a self signed certificate, so users 
#    will have to accept the security warning in the browser.
# 2. SFTP will not work, this is not ssh. File uploads can be made by copying
#    files from the browser machine to a cloud location (e.g. github) and then
#    pulling the file down with wget from the lab box, for example.
# 3. This solution does not support X11 so you can not forward GUI windows
#    over this connection. Any GUIs used on the lab system will have to be 
#    web servers accessed with new browser tabs remotely.
```sh
#!/bin/env sh
#
# Usage: ./setup.sh [desired-ubuntu-password]
#
# Then login with:
#     user: ubuntu
#     password: rx-myyyymmdd (e.g. rx-m20260127) --or--
#               <password provided on cli>
#
# This script installs wetty as a daemon listening on port 443 with a self
# signed cert on a new (untampered with) standard RX-M Ubuntu lab system. To
# connect to the system browse to: https://<ip-of-lab-vm>/wetty
#
# This is a fast websocket based terminal solution for those who cannot use
# ssh. Note that installing wetty does not disable standard ssh/key based
# login support.
#
# Caveats:
# ==============================================
# 1. While the connection is TLS it uses a self signed certificate, so users
#    will have to accept the security warning in the browser.
# 2. SFTP will not work, this is not ssh. File uploads can be made by copying
#    files from the browser machine to a cloud location (e.g. github) and then
#    pulling the file down with wget from the lab box, for example.
# 3. This solution does not support X11 so you can not forward GUI windows
#    over this connection. Any GUIs used on the lab system will have to be
#    web servers accessed with new browser tabs remotely.

set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run as root (e.g. sudo ./setup.sh [password])" >&2
  exit 1
fi

PASS="${1:-rx-m$(date +%Y%m%d)}"
WETTY_PORT="3000"
WETTY_HOST="127.0.0.1"
WETTY_BASE="/wetty"

echo "[1/9] Updating apt + installing prerequisites..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl openssl \
  openssh-server openssh-client \
  nginx

echo "[2/9] Ensuring ubuntu user exists + setting password..."
if ! id ubuntu >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" ubuntu
fi
echo "ubuntu:${PASS}" | chpasswd

echo "[3/9] Ensuring SSH password auth is enabled (for wetty -> ssh localhost)..."
SSHD_D_DIR="/etc/ssh/sshd_config.d"
mkdir -p "$SSHD_D_DIR"
cat > "${SSHD_D_DIR}/99-wetty.conf" <<'EOF'
# Managed by setup.sh (wetty)
PasswordAuthentication yes
KbdInteractiveAuthentication yes
UsePAM yes
EOF
systemctl restart ssh || systemctl restart sshd || true

echo "[4/9] Installing Node.js + npm (Ubuntu 24.04 repo) + wetty..."
apt-get install -y --no-install-recommends nodejs npm
npm install -g wetty

WETTY_BIN="$(command -v wetty || true)"
if [ -z "${WETTY_BIN}" ]; then
  echo "ERROR: wetty not found after npm install -g wetty" >&2
  exit 1
fi

echo "[5/9] Creating systemd service for wetty (bound to localhost only)..."
cat > /etc/systemd/system/wetty.service <<EOF
[Unit]
Description=WeTTY (web terminal)
After=network-online.target ssh.service
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/home/ubuntu
Environment=NODE_ENV=production
ExecStart=${WETTY_BIN} --host ${WETTY_HOST} --port ${WETTY_PORT} --base ${WETTY_BASE} --force-ssh --ssh-host localhost --ssh-user ubuntu
Restart=always
RestartSec=2
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now wetty

echo "[6/9] Generating self-signed TLS cert for nginx..."
SSL_DIR="/etc/nginx/ssl"
mkdir -p "$SSL_DIR"
chmod 700 "$SSL_DIR"

IP_ADDR="$(hostname -I 2>/dev/null | awk '{print $1}')"
CN="${IP_ADDR:-$(hostname)}"

openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "${SSL_DIR}/wetty.key" \
  -out "${SSL_DIR}/wetty.crt" \
  -days 825 \
  -subj "/CN=${CN}"

chmod 600 "${SSL_DIR}/wetty.key" "${SSL_DIR}/wetty.crt"

echo "[7/9] Configuring nginx to serve https://<host>/wetty (WebSocket reverse proxy)..."
rm -f /etc/nginx/sites-enabled/default || true

cat > /etc/nginx/sites-available/wetty <<EOF
server {
  listen 80 default_server;
  listen [::]:80 default_server;
  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl http2 default_server;
  listen [::]:443 ssl http2 default_server;

  ssl_certificate     ${SSL_DIR}/wetty.crt;
  ssl_certificate_key ${SSL_DIR}/wetty.key;

  # Optional hardening (kept minimal for lab use)
  add_header X-Content-Type-Options nosniff always;
  add_header X-Frame-Options SAMEORIGIN always;
  add_header Referrer-Policy no-referrer always;

  # WeTTY docs recommend this websocket proxy shape for /wetty
  location ^~ ${WETTY_BASE} {
    proxy_pass http://${WETTY_HOST}:${WETTY_PORT}${WETTY_BASE};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 43200000;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header Host \$http_host;
    proxy_set_header X-NginX-Proxy true;
  }

  location = / {
    return 302 ${WETTY_BASE};
  }
}
EOF

ln -sf /etc/nginx/sites-available/wetty /etc/nginx/sites-enabled/wetty
nginx -t
systemctl enable --now nginx
systemctl reload nginx

echo "[8/9] Opening firewall (if ufw is active)..."
if command -v ufw >/dev/null 2>&1; then
  if ufw status 2>/dev/null | grep -qi "Status: active"; then
    ufw allow 443/tcp || true
    ufw allow 80/tcp  || true
  fi
fi

echo "[9/9] Done."
echo "------------------------------------------------------------"
echo "Wetty URL:      https://${CN}${WETTY_BASE}"
echo "Login user:     ubuntu"
echo "Login password: ${PASS}"
echo "Note: Your browser will warn due to a self-signed certificate."
echo "Service status: systemctl status wetty --no-pager"
echo "Logs:           journalctl -u wetty -f"
echo "------------------------------------------------------------"

