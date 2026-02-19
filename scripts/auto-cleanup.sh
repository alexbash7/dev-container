#!/bin/bash
# ============================================================
# Auto-cleanup expired sandbox containers
# Run via cron every hour:
# 0 * * * * /opt/dev-sandbox/scripts/auto-cleanup.sh >> /var/log/sandbox-cleanup.log 2>&1
# ============================================================

NOW_EPOCH=$(date +%s)

for CONTAINER in $(docker ps -a --filter "label=sandbox.name" --format "{{.Names}}"); do
    EXPIRES=$(docker inspect "$CONTAINER" --format '{{index .Config.Labels "sandbox.expires"}}' 2>/dev/null)
    NAME=$(docker inspect "$CONTAINER" --format '{{index .Config.Labels "sandbox.name"}}' 2>/dev/null)

    if [ -z "$EXPIRES" ] || [ -z "$NAME" ]; then
        continue
    fi

    # Parse expiry timestamp
    EXPIRES_EPOCH=$(date -d "$EXPIRES" +%s 2>/dev/null || echo 0)

    if [ "$NOW_EPOCH" -gt "$EXPIRES_EPOCH" ] && [ "$EXPIRES_EPOCH" -gt 0 ]; then
        echo "$(date -u '+%Y-%m-%d %H:%M:%S') Deleting expired: $CONTAINER (expired: $EXPIRES)"

        # Stop and remove container
        docker rm -f "$CONTAINER" >/dev/null 2>&1

        # Remove host user
        userdel "$NAME" 2>/dev/null || true

        # Remove nginx config
        rm -f "/etc/nginx/sites-available/sandbox-${NAME}" "/etc/nginx/sites-enabled/sandbox-${NAME}"

        # Keep data for review
        echo "  Data preserved at /opt/dev-sandbox/data/${NAME}"
    fi
done

nginx -t 2>/dev/null && nginx -s reload 2>/dev/null || true
