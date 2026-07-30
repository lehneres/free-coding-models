#!/usr/bin/env bash

# Copyright (c) 2021-2026 lehneres
# Author: lehneres (https://github.com/lehneres)
# License: MIT | https://github.com/lehneres/free-coding-models/raw/main/LICENSE
# Source: https://github.com/lehneres/free-coding-models

set -e

# --- Application Variables ---
APP="Free Coding Models"
var_tags="${var_tags:-ai;router}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

# --- Proxmox Variables ---
CT_ID=${1:-500}
CT_NAME="fcm"
CT_STORAGE=$(pvesm status -content rootdir | awk 'NR>1 {print $1; exit}')
CT_TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
CT_BRIDGE=${CT_BRIDGE:-vmbr0}

# --- Colors & Symbols ---
RD="\e[1;31m"; GR="\e[1;32m"; YW="\e[1;33m"; BL="\e[1;34m"; NC="\e[0m"
GN="\e[1;32m"; CL="\e[0m"; BGN="\e[1;42m"
INFO="[INFO]"
OK="[OK]"
ERROR="[ERROR]"

function msg_info() { echo -e "${BL}${INFO}${NC} $1"; }
function msg_ok() { echo -e "${GR}${OK}${NC} $1"; }
function msg_error() { echo -e "${RD}${ERROR}${NC} $1"; }

function header_info() {
  clear
  echo -e "${BL}══════════════════════════════════════════════════════════${NC}"
  echo -e "${BL}  ${APP} Setup${NC}"
  echo -e "${BL}══════════════════════════════════════════════════════════${NC}"
}

function update_script() {
  header_info
  if ! pct status "$CT_ID" &>/dev/null; then
    msg_error "Container $CT_ID does not exist"
    exit 1
  fi
  msg_info "Updating ${APP} in CT ${CT_ID}..."
  pct exec "$CT_ID" -- bash -c "cd /opt/free-coding-models && git pull && npm install --include=dev && npm run build:web && systemctl restart fcm-daemon"
  msg_ok "Updated successfully"
  exit
}

if [[ "$1" == "update" ]]; then
  CT_ID=${2:-500}
  update_script
fi

header_info

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

msg_info "Creating LXC container (ID $CT_ID, ${var_ram}MB, ${var_cpu} cores)..."
pct create "$CT_ID" "$TEMPLATE_PATH" \
  --hostname "$CT_NAME" \
  --memory "$var_ram" \
  --cores "$var_cpu" \
  --storage "$CT_STORAGE" \
  --rootfs "$CT_STORAGE:$var_disk" \
  --net0 name=eth0,bridge="$CT_BRIDGE",ip=dhcp \
  --unprivileged "$var_unprivileged" \
  --features "keyctl=1,nesting=1" \
  --tags "$var_tags" >/dev/null
msg_ok "Container created"

msg_info "Starting container..."
pct start "$CT_ID"
sleep 5
msg_ok "Container started"

msg_info "Installing ${APP} (this takes a few minutes)..."
# Install curl first if missing
pct exec "$CT_ID" -- apt-get update -qq
pct exec "$CT_ID" -- apt-get install -y -qq curl >/dev/null
# Run install script
pct exec "$CT_ID" -- bash -c "export FUNCTIONS_FILE_PATH='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func'; bash <(curl -s https://raw.githubusercontent.com/lehneres/free-coding-models/main/scripts/proxmoxve-install.sh)"

CT_IP=$(pct exec "$CT_ID" -- sh -c 'ip -4 addr show eth0 2>/dev/null | grep -oP "inet \K[^/]+"')
[ -z "$CT_IP" ] && CT_IP="<container IP>"

msg_ok "Completed successfully!\n"
echo -e "${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${YW}Access it using the following URL:${CL}"
echo -e "${BGN}http://${CT_IP}:19280${CL}"
echo ""
echo -e "${YW}Next steps:${NC}"
echo "  1. pct enter $CT_ID"
echo "  2. Edit /root/.free-coding-models.json and add your API keys"
echo "  3. systemctl restart fcm-daemon"
echo ""
