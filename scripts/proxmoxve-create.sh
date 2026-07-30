#!/usr/bin/env bash
# Self-contained Proxmox VE helper script for free-coding-models
# Creates a Debian 12 LXC container and installs the FCM router daemon.
# Usage: bash proxmoxve-create.sh [CT_ID]

set -e

CT_ID=${1:-500}
CT_NAME="fcm"
CT_MEMORY=${CT_MEMORY:-2048}
CT_CORES=${CT_CORES:-2}
CT_DISK_SIZE=${CT_DISK_SIZE:-8}
CT_STORAGE=$(pvesm status -content rootdir | awk 'NR>1 {print $1; exit}')
CT_TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
CT_BRIDGE=${CT_BRIDGE:-vmbr0}
CT_GW=${CT_GW:-}
REPO_URL="https://github.com/lehneres/free-coding-models"

RD="\e[1;31m"; GR="\e[1;32m"; YW="\e[1;33m"; BL="\e[1;34m"; NC="\e[0m"
msg_info()  { echo -e "${BL}[INFO]${NC}  $1"; }
msg_ok()    { echo -e "${GR}[OK]${NC}    $1"; }
msg_error() { echo -e "${RD}[ERROR]${NC} $1"; }

if ! command -v pct &>/dev/null; then
  msg_error "pct not found — run this on your Proxmox VE host"
  exit 1
fi

if pct status "$CT_ID" &>/dev/null; then
  msg_error "Container ID $CT_ID already exists"
  exit 1
fi

TEMPLATE_PATH="/var/lib/vz/template/cache/$CT_TEMPLATE"
if [ ! -f "$TEMPLATE_PATH" ]; then
  msg_info "Downloading Debian 12 LXC template..."
  pveam update
  pveam download "$CT_STORAGE" "$CT_TEMPLATE"
  msg_ok "Template downloaded"
fi

msg_info "Creating LXC container (ID $CT_ID, ${CT_MEMORY}MB, ${CT_CORES} cores)..."
pct create "$CT_ID" "/var/lib/vz/template/cache/$CT_TEMPLATE" \
  --hostname "$CT_NAME" \
  --memory "$CT_MEMORY" \
  --cores "$CT_CORES" \
  --storage "$CT_STORAGE" \
  --rootfs "$CT_STORAGE:$CT_DISK_SIZE" \
  --net0 name=eth0,bridge="$CT_BRIDGE",ip=dhcp \
  --unprivileged 1 \
  --features "keyctl=1,nesting=1" \
  --tags "free-coding-models" >/dev/null
msg_ok "Container created"

msg_info "Starting container..."
pct start "$CT_ID"
sleep 5
msg_ok "Container started"

msg_info "Installing free-coding-models (this takes a few minutes)..."
pct exec "$CT_ID" -- bash <<'INSTALL_EOF'
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq git ca-certificates curl imagemagick

curl -fsSL https://deb.nodesource.com/setup_22.x | bash - &>/dev/null
apt-get install -y -qq nodejs

git clone https://github.com/lehneres/free-coding-models.git /opt/free-coding-models
cd /opt/free-coding-models

npm install --include=dev
npm run build:web

cat >/etc/systemd/system/fcm-daemon.service <<'SERVICE'
[Unit]
Description=Free Coding Models Router Daemon
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/free-coding-models
ExecStart=/usr/bin/node /opt/free-coding-models/bin/free-coding-models.js --daemon
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=FCM_HOST=0.0.0.0
Environment=FCM_PORT=19280

[Install]
WantedBy=multi-user.target
SERVICE

systemctl enable fcm-daemon
systemctl start fcm-daemon
INSTALL_EOF

CT_IP=$(pct exec "$CT_ID" -- sh -c 'ip -4 addr show eth0 2>/dev/null | grep -oP "inet \K[^/]+"')
[ -z "$CT_IP" ] && CT_IP="<container IP>"

echo ""
echo -e "${GR}══════════════════════════════════════════════════════════${NC}"
echo -e "${GR}  free-coding-models is deployed!${NC}"
echo -e "${GR}  Container:  $CT_ID ($CT_NAME)${NC}"
echo -e "${GR}  Dashboard:  http://$CT_IP:19280${NC}"
echo -e "${GR}  SSH:        pct enter $CT_ID${NC}"
echo -e "${GR}  Logs:       docker exec $CT_NAME fcm-log${NC}"
echo -e "${GR}══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YW}  Next steps:${NC}"
echo "  1. pct enter $CT_ID"
echo "  2. Edit /root/.free-coding-models.json and add your API keys"
echo "  3. Run: fcm-restart"
echo "  4. Or just use: fcm-update to pull latest + rebuild"
echo ""
