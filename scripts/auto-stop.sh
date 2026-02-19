#!/bin/bash
# ============================================================
# Auto-stop idle sandbox containers
# Run via cron every 5 minutes:
# */5 * * * * /opt/dev-sandbox/scripts/auto-stop.sh >> /var/log/sandbox-autostop.log 2>&1
# ============================================================

IDLE_MINUTES=${SANDBOX_IDLE_MINUTES:-15}

for CONTAINER in $(docker ps --filter "label=sandbox.name" --format "{{.Names}}"); do
    NAME=$(docker inspect "$CONTAINER" --format '{{index .Config.Labels "sandbox.name"}}' 2>/dev/null)
    DATA_DIR="/opt/dev-sandbox/data/${NAME}"

    # Check for active SSH sessions inside container
    SSH_SESSIONS=$(docker exec "$CONTAINER" bash -c 'who 2>/dev/null | wc -l' 2>/dev/null || echo 0)
    if [ "$SSH_SESSIONS" -gt 0 ]; then
        continue
    fi

    # Check for active code-server connections (WebSocket)
    CS_CONNECTIONS=$(docker exec "$CONTAINER" bash -c 'ss -tn state established dport = :13337 2>/dev/null | wc -l' 2>/dev/null || echo 0)
    if [ "$CS_CONNECTIONS" -gt 1 ]; then  # 1 = header line
        continue
    fi

    # Check recent file changes
    CHANGES_LOG="$DATA_DIR/logs/file_changes.log"
    if [ -f "$CHANGES_LOG" ]; then
        LAST_CHANGE=$(stat -c %Y "$CHANGES_LOG" 2>/dev/null || echo 0)
        NOW=$(date +%s)
        DIFF=$(( (NOW - LAST_CHANGE) / 60 ))
        if [ "$DIFF" -lt "$IDLE_MINUTES" ]; then
            continue
        fi
    fi

    echo "$(date -u '+%Y-%m-%d %H:%M:%S') Stopping idle: $CONTAINER (no activity for ${IDLE_MINUTES}+ min)"
    docker stop "$CONTAINER" >/dev/null 2>&1

    # Log stop event
    echo "auto-stop: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> "$DATA_DIR/logs/sessions.log" 2>/dev/null
done
