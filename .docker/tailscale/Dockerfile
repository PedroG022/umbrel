FROM tailscale/tailscale:latest

RUN apk add --no-cache bash curl jq bind-tools

WORKDIR /app

COPY register_subdomain.sh /app/register_subdomain.sh
COPY .docker/tailscale/entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/register_subdomain.sh /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
