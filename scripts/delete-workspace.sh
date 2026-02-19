#!/bin/bash
set -e

# ============================================================
# Dev Sandbox — Delete Workspace
# Removes container + host user + nginx config
# Data is preserved for review
# ============================================================

NAME="$1"
REMOVE_DATA="${2:-}"

if [ -z "$NAME" ]; then
    echo "Usage: $0 <sandbox-name> [--remove-data]"
    exit 1
fi

CONTAINER="sandbox-${NAME}"

echo "Deleting sandbox: $NAME"

# Stop and remove container
docker rm -f "$CONTAINER" 2>/dev/null || true
echo "  Container removed"

# Remove host user
userdel "$NAME" 2>/dev/null || true
echo "  Host user removed"

# Remove nginx config
rm -f "/opt/nginx/conf.d/sandbox-${NAME}.conf"
docker exec nginx-nginx-1 nginx -s reload 2>/dev/null || true
echo "  Nginx config removed"

# Optionally remove data
if [ "$REMOVE_DATA" = "--remove-data" ]; then
    rm -rf "/opt/dev-sandbox/data/${NAME}"
    echo "  Data removed"
else
    echo "  Data preserved at /opt/dev-sandbox/data/${NAME}"
fi
