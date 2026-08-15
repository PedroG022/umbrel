#!/usr/bin/env bash

# ==============================================================================
# Proxmox VE LXC Container Installer for Docker-Umbrel
# Repository: https://github.com/PedroG022/umbrel
# ==============================================================================

set -euo pipefail

# Text colors & styling
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Check if running on Proxmox VE
if ! command -v pveversion >/dev/null 2>&1; then
    echo -e "${RED}✘ Error: This script must be run directly on a Proxmox VE host.${NC}"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}✘ Error: This script must be run as root on the Proxmox host.${NC}"
    exit 1
fi

clear
cat << "EOF"
  ██████╗  ██████╗  ██████╗██╗  ██╗███████╗██████╗ 
  ██╔══██╗██╔═══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗
  ██║  ██║██║   ██║██║     █████╔╝ █████╗  ██████╔╝
  ██║  ██║██║   ██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗
  ██████╔╝╚██████╔╝╚██████╗██║  ██╗███████╗██║  ██║
  ╚═════╝  ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝
  Umbrel in Docker — Proxmox VE LXC Provisioner
EOF
echo -e "${CYAN}───────────────────────────────────────────────────────────────────${NC}"

# Auto-detect next available CT ID
NEXT_CTID=$(pvesh get /cluster/nextid)

# Auto-detect storage
DEFAULT_STORAGE=""
for storage in "local-lvm" "local-zfs" "local" "ceph" "pool"; do
    if pvesm status -storage "$storage" &>/dev/null; then
        DEFAULT_STORAGE="$storage"
        break
    fi
done

if [[ -z "$DEFAULT_STORAGE" ]]; then
    DEFAULT_STORAGE=$(pvesm status | awk 'NR>1 {print $1}' | head -n 1)
fi

echo -e "\n${BOLD}Container Configuration:${NC}"

# 1. Container ID
read -r -p "$(echo -e "${CYAN}❯ Container ID [default: ${NEXT_CTID}]: ${NC}")" CTID
CTID="${CTID:-$NEXT_CTID}"

# 2. Hostname
read -r -p "$(echo -e "${CYAN}❯ Hostname [default: umbrel]: ${NC}")" CT_HOSTNAME
CT_HOSTNAME="${CT_HOSTNAME:-umbrel}"

# 3. Disk Storage
read -r -p "$(echo -e "${CYAN}❯ Storage Pool [default: ${DEFAULT_STORAGE}]: ${NC}")" CT_STORAGE
CT_STORAGE="${CT_STORAGE:-$DEFAULT_STORAGE}"

# 4. Disk Size
read -r -p "$(echo -e "${CYAN}❯ Disk Size in GB [default: 32]: ${NC}")" CT_DISK_SIZE
CT_DISK_SIZE="${CT_DISK_SIZE:-32}"

# 5. Cores
read -r -p "$(echo -e "${CYAN}❯ CPU Cores [default: 4]: ${NC}")" CT_CORES
CT_CORES="${CT_CORES:-4}"

# 6. RAM
read -r -p "$(echo -e "${CYAN}❯ RAM in MB [default: 4096]: ${NC}")" CT_RAM
CT_RAM="${CT_RAM:-4096}"

# 7. Bridge
read -r -p "$(echo -e "${CYAN}❯ Network Bridge [default: vmbr0]: ${NC}")" CT_BRIDGE
CT_BRIDGE="${CT_BRIDGE:-vmbr0}"

# 8. IP Configuration
read -r -p "$(echo -e "${CYAN}❯ IP Assignment (dhcp or ip/cidr e.g. 192.168.1.50/24) [default: dhcp]: ${NC}")" CT_IP
CT_IP="${CT_IP:-dhcp}"

CT_GW=""
if [[ "$CT_IP" != "dhcp" ]]; then
    read -r -p "$(echo -e "${CYAN}❯ Gateway IP (e.g. 192.168.1.1): ${NC}")" CT_GW
fi

# 9. Password / SSH
read -r -s -p "$(echo -e "${CYAN}❯ Container Root Password [default: 123456]: ${NC}")" CT_PASSWORD
echo ""
CT_PASSWORD="${CT_PASSWORD:-123456}"

# 10. Git Branch
read -r -p "$(echo -e "${CYAN}❯ Umbrel Git Branch [default: refactor]: ${NC}")" GIT_BRANCH
GIT_BRANCH="${GIT_BRANCH:-refactor}"

echo -e "\n${CYAN}───────────────────────────────────────────────────────────────────${NC}"
echo -e "${BOLD}Summary of Container Settings:${NC}"
echo -e "  • CT ID:      ${GREEN}${CTID}${NC}"
echo -e "  • Hostname:   ${GREEN}${CT_HOSTNAME}${NC}"
echo -e "  • Storage:    ${GREEN}${CT_STORAGE} (${CT_DISK_SIZE}G)${NC}"
echo -e "  • CPU/RAM:    ${GREEN}${CT_CORES} Cores / ${CT_RAM} MB${NC}"
echo -e "  • Network:    ${GREEN}${CT_BRIDGE} (${CT_IP})${NC}"
echo -e "  • Git Branch: ${GREEN}${GIT_BRANCH}${NC}"
echo -e "${CYAN}───────────────────────────────────────────────────────────────────${NC}"

read -r -p "$(echo -e "${BOLD}Create and deploy container now? [Y/n]: ${NC}")" CONFIRM
if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    echo -e "${YELLOW}Aborted by user.${NC}"
    exit 0
fi

# Locate or Download Debian 12 Template
echo -e "\n${BLUE}⏳ Checking Debian 12 standard template...${NC}"
pveam update >/dev/null 2>&1 || true

TEMPLATE=$(pveam list local 2>/dev/null | awk '/debian-12-standard/ {print $1}' | sort -V | tail -n 1 || true)

if [[ -z "$TEMPLATE" ]]; then
    # Find template name from available list
    TEMPLATE_NAME=$(pveam available | awk '/debian-12-standard/ {print $2}' | sort -V | tail -n 1 || true)
    if [[ -z "$TEMPLATE_NAME" ]]; then
        TEMPLATE_NAME="debian-12-standard_12.7-1_amd64.tar.zst"
    fi
    echo -e "${YELLOW}Downloading template ${TEMPLATE_NAME}...${NC}"
    pveam download local "$TEMPLATE_NAME"
    TEMPLATE="local:vztmpl/${TEMPLATE_NAME}"
fi

echo -e "${GREEN}✓ Template ready: ${TEMPLATE}${NC}"

# Create LXC Container
echo -e "\n${BLUE}⏳ Creating LXC container ${CTID}...${NC}"

NET_CONFIG="name=eth0,bridge=${CT_BRIDGE},ip=${CT_IP}"
if [[ -n "$CT_GW" ]]; then
    NET_CONFIG="${NET_CONFIG},gw=${CT_GW}"
fi

pct create "$CTID" "$TEMPLATE" \
    --hostname "$CT_HOSTNAME" \
    --cores "$CT_CORES" \
    --memory "$CT_RAM" \
    --swap 1024 \
    --ostype debian \
    --storage "$CT_STORAGE" \
    --rootfs "${CT_STORAGE}:${CT_DISK_SIZE}" \
    --net0 "$NET_CONFIG" \
    --unprivileged 1 \
    --features nesting=1,keyctl=1 \
    --onboot 1 \
    --password "$CT_PASSWORD"

# Configure TUN device pass-through for Tailscale / VPN inside unprivileged LXC
CONF_FILE="/etc/pve/lxc/${CTID}.conf"
cat << 'EOF' >> "$CONF_FILE"

# Docker & Tailscale / VPN device pass-through
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
lxc.mount.entry: /dev/kmsg dev/kmsg none bind,create=file
EOF

echo -e "${GREEN}✓ Container ${CTID} created with Docker & TUN support.${NC}"

# Start container
echo -e "\n${BLUE}⏳ Starting container ${CTID}...${NC}"
pct start "$CTID"

# Wait for network connectivity
echo -e "${BLUE}⏳ Waiting for container network initialization...${NC}"
for i in {1..30}; do
    if pct exec "$CTID" -- ping -c 1 -W 1 8.8.8.8 &>/dev/null; then
        break
    fi
    sleep 1
done

# Provisioning inside LXC
echo -e "\n${BLUE}⏳ Installing system dependencies & Docker inside container...${NC}"

pct exec "$CTID" -- bash -c '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Update system
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    sudo \
    jq \
    avahi-utils \
    libnss-mdns \
    openssl \
    nano \
    sshpass \
    iptables

# Ensure host avahi-daemon is not conflicting with Docker avahi container
systemctl disable --now avahi-daemon avahi-daemon.socket 2>/dev/null || true

# Install Docker CE & Compose Plugin
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
'

# Clone repository
echo -e "\n${BLUE}⏳ Cloning Umbrel repository (branch: ${GIT_BRANCH})...${NC}"
pct exec "$CTID" -- bash -c "
git clone -b ${GIT_BRANCH} https://github.com/PedroG022/umbrel.git /root/umbrel
chmod +x /root/umbrel/setup.sh /root/umbrel/register_subdomain.sh /root/umbrel/entrypoint.sh 2>/dev/null || true
"

# Get Container IP
CONTAINER_IP=$(pct exec "$CTID" -- ip -4 addr show eth0 | awk '/inet / {print $2}' | cut -d/ -f1 || echo "DHCP")

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}✔ Umbrel LXC Container Successfully Deployed!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  • ${BOLD}Container ID:${NC} ${CTID}"
echo -e "  • ${BOLD}IP Address:${NC}   ${CYAN}${CONTAINER_IP}${NC}"
echo -e "  • ${BOLD}Location:${NC}     /root/umbrel"
echo ""
echo -e "${BOLD}To start the Umbrel setup wizard:${NC}"
echo -e "  1. Enter container console:"
echo -e "     ${CYAN}pct enter ${CTID}${NC}"
echo -e "  2. Run setup script:"
echo -e "     ${CYAN}cd /root/umbrel && ./setup.sh${NC}"
echo ""
echo -e "Alternatively via SSH:"
echo -e "     ${CYAN}ssh root@${CONTAINER_IP}${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
