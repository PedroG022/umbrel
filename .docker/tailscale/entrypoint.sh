#!/usr/bin/env bash
set -e

# Background task: wait for Tailscale IPv4 address and register DNS record
(
    echo "⌛ Waiting for Tailscale IPv4 address..."
    TS_IP=""
    while [ -z "$TS_IP" ]; do
        sleep 2
        TS_IP=$(tailscale ip -4 2>/dev/null || true)
    done

    echo "✅ Tailscale IP obtained: $TS_IP"
    echo "🚀 Automatically registering subdomain DNS record with Tailscale IP..."
    
    cd /app
    if [ -f "/app/.env" ]; then
        export ENV_FILE="/app/.env"
    fi

    # Run register_subdomain.sh using .env options and obtained Tailscale IP
    ./register_subdomain.sh "${SUBDOMAIN:-}" "$TS_IP" || echo "⚠️ Warning: register_subdomain.sh exited with status $?"
)&

# Execute default Tailscale containerboot process as PID 1
exec /usr/local/bin/containerboot "$@"
