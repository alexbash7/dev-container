#!/bin/bash
set -e

# ============================================================
# 0. Set up user with correct name and password
# ============================================================
USERNAME="${CANDIDATE_NAME:-coder}"
if [ "$USERNAME" != "coder" ] && ! id "$USERNAME" >/dev/null 2>&1; then
    usermod -l "$USERNAME" coder 2>/dev/null || true
    groupmod -n "$USERNAME" coder 2>/dev/null || true
    sed -i "s/AllowUsers coder/AllowUsers $USERNAME/" /etc/ssh/sshd_config
fi
HOME_DIR="/home/coder"

if [ -n "$SANDBOX_PASSWORD" ]; then
    echo "$USERNAME:$SANDBOX_PASSWORD" | chpasswd
fi

# ============================================================
# 1. Fix permissions on mounted volumes
# ============================================================
chown -R $USERNAME:$USERNAME $HOME_DIR/workspace

# Bash history — hidden in user's home
mkdir -p $HOME_DIR/.cache
touch "$HOME_DIR/.cache/.system_journal"
chown -R $USERNAME:$USERNAME $HOME_DIR/.cache

# code-server data dirs
mkdir -p $HOME_DIR/.code-server/User $HOME_DIR/.config $HOME_DIR/.local
chown -R $USERNAME:$USERNAME $HOME_DIR/.code-server $HOME_DIR/.config $HOME_DIR/.local

# ============================================================
# 2. Initialize workspace (clone task on first run)
# ============================================================
INIT_MARKER="/var/log/sandbox/.initialized"
if [ ! -f "$INIT_MARKER" ] && [ -n "$TASK_REPO" ]; then
    echo "Initializing workspace: TASK_REPO=$TASK_REPO TASK_FOLDER=$TASK_FOLDER" >> /var/log/sandbox/entrypoint.log
    sudo -u $USERNAME TASK_REPO="$TASK_REPO" TASK_FOLDER="$TASK_FOLDER" CANDIDATE_NAME="$CANDIDATE_NAME" bash /usr/lib/sandbox/startup.sh >> /var/log/sandbox/entrypoint.log 2>&1
    echo "startup.sh exit code: $?" >> /var/log/sandbox/entrypoint.log
    touch "$INIT_MARKER"
fi

# ============================================================
# 3. Record session start
# ============================================================
echo "start: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> /var/log/sandbox/sessions.log

# ============================================================
# 4. Generate SSH host keys if missing
# ============================================================
ssh-keygen -A 2>/dev/null

# ============================================================
# 5. Start SSH server
# ============================================================
/usr/sbin/sshd

# ============================================================
# 6. Start code-server (foreground)
# ============================================================
export PASSWORD="$SANDBOX_PASSWORD"
exec sudo -u $USERNAME env PASSWORD="$SANDBOX_PASSWORD" /opt/code-server/bin/code-server \
    --auth password \
    --port 13337 \
    --host 0.0.0.0 \
    --user-data-dir $HOME_DIR/.code-server \
    --welcome-text "Enter your password to access the workspace." \
    $HOME_DIR/workspace
