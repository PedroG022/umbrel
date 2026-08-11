#!/usr/bin/env bash
#
# Register/Update a subdomain DNS record via Hostinger API
#
# Environment variables loaded from .env (if present):
#   API_TOKEN       Hostinger API Bearer Token (Required)
#   DOMAIN          Parent domain, e.g., "example.com" (Required)
#   SUBDOMAIN       Subdomain name or full name, e.g., "app" or "app.example.com"
#   RECORD_CONTENT  Target IP address or domain (e.g., "1.2.3.4" or "cname.target.com")
#   RECORD_TYPE     DNS record type: A, CNAME, AAAA, TXT (Default: "A")
#   RECORD_TTL      Time to live in seconds (Default: 300)
#   OVERWRITE       Replace existing zone records if true (Default: false)
#   API_BASE_URL    Base Hostinger API URL (Default: "https://developers.hostinger.com/api/dns/v1/zones")

set -euo pipefail

# 1. Load .env file if available
ENV_FILE="${ENV_FILE:-.env}"
if [ -f "$ENV_FILE" ]; then
    echo "📄 Loading configuration from $ENV_FILE..."
    # Export vars without overwriting already exported shell vars
    set -o allexport
    source "$ENV_FILE"
    set +o allexport
fi

# 2. Allow CLI parameters to override env variables
# Usage: ./register_subdomain.sh [SUBDOMAIN] [RECORD_CONTENT] [RECORD_TYPE] [RECORD_TTL]
SUBDOMAIN="${1:-${SUBDOMAIN:-}}"
RECORD_CONTENT="${2:-${RECORD_CONTENT:-}}"
RECORD_TYPE="${3:-${RECORD_TYPE:-A}}"
RECORD_TTL="${4:-${RECORD_TTL:-300}}"

API_TOKEN="${API_TOKEN:-}"
DOMAIN="${DOMAIN:-}"
OVERWRITE="${OVERWRITE:-false}"
API_BASE_URL="${API_BASE_URL:-https://developers.hostinger.com/api/dns/v1/zones}"

# 3. Input validation
MISSING_VARS=()
if [ -z "$API_TOKEN" ]; then MISSING_VARS+=("API_TOKEN"); fi
if [ -z "$DOMAIN" ]; then MISSING_VARS+=("DOMAIN"); fi
if [ -z "$SUBDOMAIN" ]; then MISSING_VARS+=("SUBDOMAIN"); fi
if [ -z "$RECORD_CONTENT" ]; then MISSING_VARS+=("RECORD_CONTENT (or TARGET IP/URL)"); fi

if [ ${#MISSING_VARS[@]} -ne 0 ]; then
    echo "❌ Error: Missing required parameter(s): ${MISSING_VARS[*]}"
    echo ""
    echo "Usage:"
    echo "  1. Set variables in .env file (API_TOKEN, DOMAIN, SUBDOMAIN, RECORD_CONTENT)"
    echo "  2. Or pass them via CLI:"
    echo "     ./register_subdomain.sh <subdomain> <content/IP> [type] [ttl]"
    echo ""
    echo "Example .env file:"
    echo "  API_TOKEN=\"your_hostinger_bearer_token\""
    echo "  DOMAIN=\"example.com\""
    echo "  SUBDOMAIN=\"app\""
    echo "  RECORD_CONTENT=\"192.0.2.1\""
    echo "  RECORD_TYPE=\"A\""
    echo "  RECORD_TTL=300"
    exit 1
fi

# Strip parent domain if SUBDOMAIN was passed as full FQDN (e.g. app.example.com -> app)
SUBDOMAIN_SHORT="${SUBDOMAIN%.${DOMAIN}}"

# 4. Prepare JSON Payload
# Hostinger API schema expects a top-level "zone" array containing record definitions.
PAYLOAD=$(cat <<EOF
{
  "zone": [
    {
      "name": "${SUBDOMAIN_SHORT}",
      "type": "${RECORD_TYPE}",
      "records": [
        {
          "content": "${RECORD_CONTENT}"
        }
      ],
      "ttl": ${RECORD_TTL}
    }
  ],
  "overwrite": ${OVERWRITE}
}
EOF
)

echo "🌐 Domain: $DOMAIN"
echo "📌 Registering Subdomain: $SUBDOMAIN_SHORT.$DOMAIN ($RECORD_TYPE -> $RECORD_CONTENT, TTL: ${RECORD_TTL}s)"

# 5. Validate payload with Hostinger API prior to applying
VALIDATE_URL="${API_BASE_URL}/${DOMAIN}/validate"
echo "🔍 Validating DNS record with Hostinger API..."

VALIDATE_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "$VALIDATE_URL" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$PAYLOAD")

VALIDATE_BODY=$(echo "$VALIDATE_RESPONSE" | head -n -1)
VALIDATE_STATUS=$(echo "$VALIDATE_RESPONSE" | tail -n 1)

if [ "$VALIDATE_STATUS" -ne 200 ] && [ "$VALIDATE_STATUS" -ne 204 ]; then
    echo "⚠️ Validation Notice (HTTP $VALIDATE_STATUS): $VALIDATE_BODY"
else
    echo "✅ Validation successful."
fi

# 6. Send request to update/create DNS record
UPDATE_URL="${API_BASE_URL}/${DOMAIN}"
echo "🚀 Sending DNS record update request to Hostinger API..."

RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X PUT "$UPDATE_URL" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$PAYLOAD")

BODY=$(echo "$RESPONSE" | head -n -1)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)

# 7. Check Response Status
if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
    echo "🎉 Success! Subdomain '$SUBDOMAIN_SHORT.$DOMAIN' record created/updated successfully. (HTTP $HTTP_STATUS)"
    if command -v jq &>/dev/null; then
        echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    else
        echo "$BODY"
    fi
else
    echo "❌ Failed to register subdomain (HTTP $HTTP_STATUS)."
    if command -v jq &>/dev/null; then
        echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    else
        echo "$BODY"
    fi
    # Proceed to DNS check anyway to show current propagation status
fi

# 8. Perform DNS Lookups (dig / nslookup) with Cloudflare and Google DNS
FQDN="${SUBDOMAIN_SHORT}.${DOMAIN}"
echo ""
echo "🔎 Performing DNS lookup for '$FQDN' ($RECORD_TYPE)..."

check_dns_resolver() {
    local provider="$1"
    local server="$2"

    echo "  🔹 Resolver: $provider ($server)"
    if command -v dig &>/dev/null; then
        local res
        res=$(dig +short "$RECORD_TYPE" "$FQDN" "@$server" 2>/dev/null || true)
        if [ -n "$res" ]; then
            echo "$res" | sed 's/^/     Answer: /'
        else
            echo "     Answer: (No record found or not propagated yet)"
        fi
    elif command -v nslookup &>/dev/null; then
        local res
        res=$(nslookup -type="$RECORD_TYPE" "$FQDN" "$server" 2>/dev/null | grep -E "Address:|Address :" | tail -n +2 || true)
        if [ -n "$res" ]; then
            echo "$res" | sed 's/^/     Answer: /'
        else
            echo "     Answer: (No record found or not propagated yet)"
        fi
    else
        echo "     (Neither 'dig' nor 'nslookup' is installed)"
    fi
}

check_dns_resolver "Cloudflare" "1.1.1.1"
check_dns_resolver "Google" "8.8.8.8"

if [ "$HTTP_STATUS" -lt 200 ] || [ "$HTTP_STATUS" -ge 300 ]; then
    exit 1
fi

