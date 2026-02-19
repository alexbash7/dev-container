#!/bin/bash
set -e

# ============================================================
# Dev Sandbox — Create Workspace
# Creates a Docker container + host user + nginx config
# ============================================================

SANDBOX_NAME=""
TASK_REPO="https://github.com/alexbash7/tests.git"
TASK_FOLDER=""
PASSWORD=""
CPU="0.5"
MEMORY="512m"
EXPIRES_HOURS=72
JF_ID=""
SANDBOX_HOST="code.trafflume.com"

while [[ $# -gt 0 ]]; do
    case $1 in
        --name) SANDBOX_NAME="$2"; shift 2;;
        --task-repo) TASK_REPO="$2"; shift 2;;
        --task-folder) TASK_FOLDER="$2"; shift 2;;
        --password) PASSWORD="$2"; shift 2;;
        --cpu) CPU="$2"; shift 2;;
        --memory) MEMORY="$2"; shift 2;;
        --jf-id) JF_ID="$2"; shift 2;;
        --expires) EXPIRES_HOURS="$2"; shift 2;;
        *) echo "Unknown: $1"; exit 1;;
    esac
done

if [ -z "$SANDBOX_NAME" ]; then
    echo "Usage: $0 --name <name> [--task-folder <folder>] [--password <pass>]"
    exit 1
fi

# Generate password if not provided
if [ -z "$PASSWORD" ]; then
    PASSWORD=$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9' | head -c8)
fi

CONTAINER="sandbox-${SANDBOX_NAME}"
DATA_DIR="/opt/dev-sandbox/data/${SANDBOX_NAME}"
EXPIRES_AT=$(date -u -d "+${EXPIRES_HOURS} hours" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v+${EXPIRES_HOURS}H '+%Y-%m-%dT%H:%M:%SZ')
DOMAIN="${SANDBOX_NAME}.${SANDBOX_HOST}"

# ============================================================
# 1. Check if already exists
# ============================================================
if docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "Error: Container $CONTAINER already exists" >&2
    exit 1
fi

# ============================================================
# 2. Build image if needed
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if ! docker image inspect dev-sandbox:latest >/dev/null 2>&1; then
    echo "Building dev-sandbox image..." >&2
    docker build -t dev-sandbox:latest "$SCRIPT_DIR/docker/"
fi

# ============================================================
# 3. Create data directories
# ============================================================
mkdir -p "$DATA_DIR/workspace" "$DATA_DIR/logs"

# ============================================================
# 4. Create container (stopped)
# ============================================================
docker create \
    --name "$CONTAINER" \
    --hostname "$SANDBOX_NAME" \
    --cpus="$CPU" \
    --memory="$MEMORY" \
    --label sandbox.name="$SANDBOX_NAME" \
    --label sandbox.jf_id="$JF_ID" \
    --label sandbox.task_folder="$TASK_FOLDER" \
    --label sandbox.password="$PASSWORD" \
    --label sandbox.expires="$EXPIRES_AT" \
    --label sandbox.created="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --label sandbox.subdomain="$DOMAIN" \
    -e SANDBOX_PASSWORD="$PASSWORD" \
    -e TASK_REPO="$TASK_REPO" \
    -e TASK_FOLDER="$TASK_FOLDER" \
    -e CANDIDATE_NAME="$SANDBOX_NAME" \
    -v "$DATA_DIR/workspace:/home/coder/workspace" \
    -v "$DATA_DIR/logs:/var/log/sandbox" \
    -p 0:22 \
    -p 0:13337 \
    dev-sandbox:latest >/dev/null

# ============================================================
# 5. Start briefly to get assigned ports, then stop
# ============================================================
docker start "$CONTAINER" >/dev/null
sleep 3
SSH_PORT=$(docker port "$CONTAINER" 22 2>/dev/null | head -1 | cut -d: -f2)
WEB_PORT=$(docker port "$CONTAINER" 13337 2>/dev/null | head -1 | cut -d: -f2)
docker stop "$CONTAINER" >/dev/null 2>&1

# Save ports as labels (docker doesn't allow updating labels, so save to file)
echo "$SSH_PORT" > "$DATA_DIR/ssh_port"
echo "$WEB_PORT" > "$DATA_DIR/web_port"

# ============================================================
# 6. Create host user for SSH auto-start
# ============================================================
SHELL_PATH="/usr/local/bin/sandbox-shell"
if ! id "$SANDBOX_NAME" >/dev/null 2>&1; then
    useradd -M -s "$SHELL_PATH" "$SANDBOX_NAME" 2>/dev/null || true
    echo "${SANDBOX_NAME}:${PASSWORD}" | chpasswd
fi

# ============================================================
# 7. Create nginx config
# ============================================================
NGINX_CONF="/etc/nginx/sites-available/sandbox-${SANDBOX_NAME}"
cat > "$NGINX_CONF" << NGINX
upstream sandbox_${SANDBOX_NAME//-/_} {
    server 127.0.0.1:${WEB_PORT};
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${SANDBOX_HOST}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${SANDBOX_HOST}/privkey.pem;

    location / {
        proxy_pass http://sandbox_${SANDBOX_NAME//-/_};
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_set_header Accept-Encoding gzip;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_http_version 1.1;

        # If container is stopped, nginx gets 502 → trigger auto-start
        error_page 502 = @start_container;
    }

    location @start_container {
        default_type text/html;
        return 200 '<!DOCTYPE html>
<html>
<head><title>Starting workspace...</title>
<meta http-equiv="refresh" content="5">
<style>body{background:#1e1e1e;color:#fff;display:flex;justify-content:center;align-items:center;height:100vh;font-family:sans-serif;flex-direction:column}
.spinner{border:4px solid #333;border-top:4px solid #0078d4;border-radius:50%;width:40px;height:40px;animation:spin 1s linear infinite}
@keyframes spin{0%{transform:rotate(0deg)}100%{transform:rotate(360deg)}}</style>
</head>
<body><div class="spinner"></div><p style="margin-top:20px">Starting your workspace...</p>
<script>fetch("/api/start").then(()=>setTimeout(()=>location.reload(),5000))</script>
</body></html>';
    }

    location = /api/start {
        content_by_lua_block {
            os.execute("docker start sandbox-${SANDBOX_NAME} 2>/dev/null &")
            ngx.say('{"status":"starting"}')
        }
    }
}
NGINX

ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/sandbox-${SANDBOX_NAME}" 2>/dev/null
nginx -t 2>/dev/null && nginx -s reload 2>/dev/null || true

# ============================================================
# 8. Output credentials as JSON
# ============================================================
cat << OUTPUT
{
    "name": "${SANDBOX_NAME}",
    "container": "${CONTAINER}",
    "password": "${PASSWORD}",
    "ssh_port": ${SSH_PORT},
    "web_port": ${WEB_PORT},
    "ssh_command": "ssh ${SANDBOX_NAME}@${SANDBOX_HOST}",
    "browser_url": "https://${DOMAIN}",
    "expires_at": "${EXPIRES_AT}",
    "jf_id": "${JF_ID}"
}
OUTPUT
