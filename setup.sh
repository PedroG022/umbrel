#!/usr/bin/env bash
# ==============================================================================
# Umbrel Initial Setup Wizard (setup.sh)
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info()    { printf "${CYAN}❯${NC} %s\n" "$*"; }
success() { printf "${GREEN}✔${NC} %s\n" "$*"; }
warn()    { printf "${YELLOW}⚠${NC} %s\n" "$*"; }
error()   { printf "${RED}✖ %s${NC}\n" "$*" >&2; }
header()  {
    echo -e "\n${BLUE}${BOLD}=== $1 ===${NC}\n"
}

BANNER() {
    cat << "EOF"
  _    _           _                _ 
 | |  | |         | |              | |
 | |  | |_ __ ___ | |__  _ __  ___ | |
 | |  | | '_ ` _ \| '_ \| '__|/ _ \| |
 | |__| | | | | | | |_) | |  |  __/| |
  \____/|_| |_| |_|_.__/|_|   \___||_|
  
  Interactive Configuration Wizard
==================================================
EOF
}

# ------------------------------------------------------------------------------
# Auto-detection Utilities
# ------------------------------------------------------------------------------
detect_tailscale_ip() {
    if command -v tailscale &>/dev/null; then
        tailscale ip -4 2>/dev/null || true
    else
        ip -4 addr show tailscale0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true
    fi
}

detect_tailscale_status() {
    if command -v tailscale &>/dev/null; then
        tailscale status --json 2>/dev/null || true
    fi
}

detect_lan_ip() {
    ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "127.0.0.1"
}

detect_lan_interface() {
    ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}' || echo "eth0"
}

# ------------------------------------------------------------------------------
# Default State
# ------------------------------------------------------------------------------
ENV_FILE=".env"
MODE=""
LOCAL_HOSTNAME="umbrel"
LOCAL_DOMAIN="local"
AVAHI_INTERFACE="$(detect_lan_interface)"

DOMAIN=""
SUBDOMAIN="c"
DNS_PROVIDER="hostinger"
API_TOKEN=""
ACME_EMAIL=""
RECORD_CONTENT="$(detect_tailscale_ip)"
[ -z "$RECORD_CONTENT" ] && RECORD_CONTENT="$(detect_lan_ip)"

TAILSCALE_HOSTNAME="umbrel"
TAILNET_NAME=""

ENABLE_TLS="false"
ENABLE_ACME_DNS="false"
TLS_CERT_RESOLVER=""
TRAEFIK_HOST_RULE=""

# ------------------------------------------------------------------------------
# Interactive Wizard
# ------------------------------------------------------------------------------
run_interactive() {
    BANNER

    echo -e "Choose an ${BOLD}Operation Mode${NC} for this Umbrel instance:\n"
    echo -e "  ${BOLD}[1] Local Network (mDNS)${NC} ⭐"
    echo -e "      • Accessible across your LAN at ${CYAN}http://umbrel.local${NC}"
    echo -e "      • Zero-configuration, no external domain or API keys required."
    echo ""
    echo -e "  ${BOLD}[2] Private Domain via VPN with SSL (Let's Encrypt DNS-01)${NC}"
    echo -e "      • Accessible at ${CYAN}https://<subdomain>.<domain>${NC} over private VPN (Tailscale/WireGuard)"
    echo -e "      • Automatic public TLS/SSL certs via DNS challenge (Hostinger / Cloudflare)."
    echo ""
    echo -e "  ${BOLD}[3] Tailscale MagicDNS (*.ts.net)${NC}"
    echo -e "      • Accessible at ${CYAN}https://<node>.<tailnet>.ts.net${NC} within your tailnet"
    echo -e "      • Direct access using Tailscale MagicDNS."
    echo ""

    while true; do
        read -rp "Select mode [1-3] (Default: 1): " choice
        choice="${choice:-1}"
        case "$choice" in
            1) MODE="1"; break ;;
            2) MODE="2"; break ;;
            3) MODE="3"; break ;;
            *) warn "Invalid selection. Please enter 1, 2, or 3." ;;
        esac
    done

    case "$MODE" in
        1)
            header "Mode 1: Local Network (mDNS)"
            read -rp "Local hostname [Default: umbrel]: " in_host
            LOCAL_HOSTNAME="${in_host:-umbrel}"
            
            read -rp "Local domain [Default: local]: " in_dom
            LOCAL_DOMAIN="${in_dom:-local}"
            
            read -rp "Network interface [Default: ${AVAHI_INTERFACE}]: " in_iface
            AVAHI_INTERFACE="${in_iface:-$AVAHI_INTERFACE}"

            TRAEFIK_HOST_RULE="Host(\`${LOCAL_HOSTNAME}.${LOCAL_DOMAIN}\`)"
            TRAEFIK_ENTRYPOINTS="web"
            APP_ENTRYPOINTS="web"
            APP_ENABLE_TLS="false"
            ENABLE_TLS="false"
            ENABLE_ACME_DNS="false"
            TLS_CERT_RESOLVER=""
            TLS_DOMAIN_MAIN=""
            TLS_DOMAIN_SANS=""
            info "Target URL: http://${LOCAL_HOSTNAME}.${LOCAL_DOMAIN}/"
            ;;

        2)
            header "Mode 2: Private Domain via VPN with Let's Encrypt DNS-01"
            
            while [ -z "$DOMAIN" ]; do
                read -rp "Root Domain (e.g., my.domain): " DOMAIN
            done

            read -rp "Subdomain [Default: umbrel]: " in_sub
            SUBDOMAIN="${in_sub:-umbrel}"

            echo -e "\nSupported DNS Providers for ACME DNS Challenge:"
            echo -e "  1) Hostinger"
            echo -e "  2) Cloudflare"
            read -rp "Select DNS provider [1-2] (Default: 1): " dns_choice
            dns_choice="${dns_choice:-1}"
            if [ "$dns_choice" = "2" ]; then
                DNS_PROVIDER="cloudflare"
            else
                DNS_PROVIDER="hostinger"
            fi

            while [ -z "$API_TOKEN" ]; do
                read -rp "${DNS_PROVIDER^} API Token: " API_TOKEN
            done

            while [ -z "$ACME_EMAIL" ]; do
                read -rp "Email for Let's Encrypt notifications: " ACME_EMAIL
            done

            read -rp "Target VPN IP address [Default: ${RECORD_CONTENT}]: " in_ip
            RECORD_CONTENT="${in_ip:-$RECORD_CONTENT}"

            TRAEFIK_HOST_RULE="Host(\`${SUBDOMAIN}.${DOMAIN}\`)"
            TRAEFIK_ENTRYPOINTS="websecure"
            APP_ENTRYPOINTS="websecure"
            APP_ENABLE_TLS="true"
            ENABLE_TLS="true"
            ENABLE_ACME_DNS="true"
            TLS_CERT_RESOLVER="dnsresolver"
            TLS_DOMAIN_MAIN="${SUBDOMAIN}.${DOMAIN}"
            TLS_DOMAIN_SANS="*.${SUBDOMAIN}.${DOMAIN}"

            info "Target URL: https://${SUBDOMAIN}.${DOMAIN}/ (points to ${RECORD_CONTENT})"
            info "Wildcard SSL Domain: *.${SUBDOMAIN}.${DOMAIN}"

            # Optional: Register DNS Record immediately if register_subdomain.sh is present
            if [ -f "./register_subdomain.sh" ] && [ "$DNS_PROVIDER" = "hostinger" ]; then
                echo ""
                read -rp "Would you like to register/update the DNS record on Hostinger now? [Y/n]: " do_dns
                do_dns="${do_dns:-Y}"
                if [[ "$do_dns" =~ ^[Yy]$ ]]; then
                    info "Registering DNS records (main and wildcard)..."
                    API_TOKEN="$API_TOKEN" DOMAIN="$DOMAIN" SUBDOMAIN="$SUBDOMAIN" RECORD_CONTENT="$RECORD_CONTENT" ./register_subdomain.sh || warn "DNS registration returned non-zero code. You may configure it manually."
                fi
            fi
            ;;

        3)
            header "Mode 3: Tailscale MagicDNS"
            
            ts_detected_name=""
            ts_detected_tailnet=""
            if command -v tailscale &>/dev/null; then
                ts_status=$(detect_tailscale_status)
                if [ -n "$ts_status" ]; then
                    ts_detected_name=$(echo "$ts_status" | grep -oP '"Self":\s*{\s*"DNSName":\s*"\K[^"]+' | cut -d. -f1 || true)
                    ts_detected_tailnet=$(echo "$ts_status" | grep -oP '"Self":\s*{\s*"DNSName":\s*"\K[^"]+' | cut -d. -f2- || true)
                fi
            fi

            [ -z "$ts_detected_name" ] && ts_detected_name="umbrel"

            read -rp "Tailscale Machine Name [Default: ${ts_detected_name}]: " in_ts_name
            TAILSCALE_HOSTNAME="${in_ts_name:-$ts_detected_name}"

            read -rp "Tailnet Domain (e.g. your-tailnet.ts.net) [Default: ${ts_detected_tailnet}]: " in_tailnet
            TAILNET_NAME="${in_tailnet:-$ts_detected_tailnet}"

            if [ -n "$TAILNET_NAME" ]; then
                FULL_TS_FQDN="${TAILSCALE_HOSTNAME}.${TAILNET_NAME%.}"
            else
                FULL_TS_FQDN="${TAILSCALE_HOSTNAME}"
            fi

            TRAEFIK_HOST_RULE="Host(\`${FULL_TS_FQDN}\`)"
            TRAEFIK_ENTRYPOINTS="web"
            APP_ENTRYPOINTS="web"
            APP_ENABLE_TLS="false"
            ENABLE_TLS="false"
            ENABLE_ACME_DNS="false"
            TLS_CERT_RESOLVER=""
            TLS_DOMAIN_MAIN=""
            TLS_DOMAIN_SANS=""

            info "Target URL: http://${FULL_TS_FQDN}/"
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Write .env Configuration
# ------------------------------------------------------------------------------
write_env() {
    header "Saving Configuration"
    
    mkdir -p ./umbrel/traefik
    touch ./umbrel/traefik/acme.json
    chmod 600 ./umbrel/traefik/acme.json

    cat << EOF > "$ENV_FILE"
# ==============================================================================
# Umbrel Generated Configuration
# Generated on: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# ==============================================================================
OPERATION_MODE=${MODE}

# Mode 1: Local mDNS
LOCAL_HOSTNAME=${LOCAL_HOSTNAME}
LOCAL_DOMAIN=${LOCAL_DOMAIN}
AVAHI_INTERFACE=${AVAHI_INTERFACE}

# Mode 2: Private Domain via VPN
DOMAIN="${DOMAIN}"
SUBDOMAIN="${SUBDOMAIN}"
DNS_PROVIDER="${DNS_PROVIDER}"
API_TOKEN="${API_TOKEN}"
HOSTINGER_API_TOKEN="${API_TOKEN}"
CLOUDFLARE_DNS_API_TOKEN="${API_TOKEN}"
ACME_EMAIL="${ACME_EMAIL}"
RECORD_CONTENT="${RECORD_CONTENT}"
RECORD_TYPE="A"
RECORD_TTL=300
OVERWRITE=true

# Mode 3: Tailscale
TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME}"
TAILNET_NAME="${TAILNET_NAME}"

# Traefik & SSL Routing Parameters
TRAEFIK_HOST_RULE='${TRAEFIK_HOST_RULE}'
TRAEFIK_ENTRYPOINTS="${TRAEFIK_ENTRYPOINTS:-web}"
APP_ENTRYPOINTS="${APP_ENTRYPOINTS:-web}"
APP_ENABLE_TLS=${APP_ENABLE_TLS:-false}
ENABLE_TLS=${ENABLE_TLS}
ENABLE_ACME_DNS=${ENABLE_ACME_DNS}
TLS_CERT_RESOLVER="${TLS_CERT_RESOLVER}"
TLS_DOMAIN_MAIN="${TLS_DOMAIN_MAIN:-}"
TLS_DOMAIN_SANS="${TLS_DOMAIN_SANS:-}"
EOF

    success "Configuration written to ${ENV_FILE}"
}

# ------------------------------------------------------------------------------
# Launch Docker Stack
# ------------------------------------------------------------------------------
start_stack() {
    header "Deploying Docker Compose Stack"
    
    info "Running: docker compose up -d"
    docker compose up -d

    echo ""
    success "Umbrel is starting up!"
    case "$MODE" in
        1)
            echo -e "🌐 Access your dashboard at: ${GREEN}${BOLD}http://${LOCAL_HOSTNAME}.${LOCAL_DOMAIN}/${NC}\n"
            ;;
        2)
            echo -e "🌐 Access your dashboard at: ${GREEN}${BOLD}https://${SUBDOMAIN}.${DOMAIN}/${NC}\n"
            ;;
        3)
            echo -e "🌐 Access your dashboard at: ${GREEN}${BOLD}http://${FULL_TS_FQDN}/${NC}\n"
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    run_interactive
    write_env
    
    echo ""
    read -rp "Would you like to start Umbrel now? [Y/n]: " do_start
    do_start="${do_start:-Y}"
    if [[ "$do_start" =~ ^[Yy]$ ]]; then
        start_stack
    else
        info "Setup complete. You can start the stack anytime using: docker compose up -d"
    fi
}

main "$@"
