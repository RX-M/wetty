#!/bin/env sh
#
# Usage: sudo ./setup.sh [desired-ubuntu-password]
#
# This script installs wetty as a daemon listening on port 443 with a self
# signed cert on a new (untampered with) standard RX-M Ubuntu lab system. To
# connect to the system browse to: https://<ip-of-lab-vm>/wetty
#
# Then login with:
#     user: ubuntu
#     password: rx-myyyymmdd (e.g. rx-m20260127) --or--
#               <password provided on cli>
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

WETTY_PORT="80"
WETTY_HOST="0.0.0.0"
WETTY_BASE="/wetty"
PUB_IP=$(curl -s https://icanhazip.com)


echo "[1/6] Updating apt + installing prerequisites..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends ca-certificates curl openssl build-essential make


echo "[2/6] Ensuring ubuntu user exists + setting password..."
if ! id ubuntu >/dev/null 2>&1; then
  adduser --disabled-password --comment "" ubuntu
fi
echo "ubuntu:${PASS}" | chpasswd


echo "[3/6] Enabling SSH password auth..."
sed -i '/PasswordAuthentication/d' /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
sed -i '/PasswordAuthentication/d' /etc/ssh/sshd_config
echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
SSHD_D_DIR="/etc/ssh/sshd_config.d"
mkdir -p "$SSHD_D_DIR"
cat > "${SSHD_D_DIR}/99-wetty.conf" <<'EOF'
# Managed by rx-m-wetty-setup.sh
PasswordAuthentication yes
KbdInteractiveAuthentication yes
UsePAM yes
EOF
systemctl restart ssh


echo "[4/6] Installing Node.js + npm, then installing wetty..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs
npm install -g wetty
WETTY_BIN=`which wetty`


echo "[5/6] Creating systemd service for wetty..."
mkdir -p /var/lib/wetty
cat > /etc/systemd/system/wetty.service <<EOF
# systemd unit file /etc/systemd/system/wetty.service
[Unit]
Description=Wetty Web Terminal
After=ssh.service
[Service]
Type=simple
WorkingDirectory=/var/lib/wetty
ExecStart=${WETTY_BIN} -p ${WETTY_PORT} --base ${WETTY_BASE} --force-ssh
TimeoutStopSec=20
KillMode=mixed
Restart=always
RestartSec=2
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now wetty


echo "[6/6] Done."
echo "------------------------------------------------------------"
echo "Wetty URL:      https://${PUB_IP}:${WETTY_PORT}${WETTY_BASE}"
echo "Login user:     ubuntu"
echo "Login password: ${PASS}"
echo "Service status: systemctl status wetty --no-pager -l"
echo "Logs:           journalctl -u wetty -f"
echo "------------------------------------------------------------"

