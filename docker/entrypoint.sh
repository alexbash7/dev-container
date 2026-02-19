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
# Workspace — owned by user
chown -R $USERNAME:$USERNAME $HOME_DIR/workspace

# Logs — root-owned dir, but create user-writable files
chown root:root /var/log/sandbox
chmod 700 /var/log/sandbox

# Pre-create all log files with correct permissions
touch /var/log/sandbox/.bash_history_audit
chmod 622 /var/log/sandbox/.bash_history_audit
chown $USERNAME:$USERNAME /var/log/sandbox/.bash_history_audit

touch /var/log/sandbox/file_changes.log
touch /var/log/sandbox/sessions.log
touch /var/log/sandbox/entrypoint.log
touch /var/log/sandbox/.initialized 2>/dev/null || true

# code-server data dir
mkdir -p $HOME_DIR/.code-server/User
chown -R $USERNAME:$USERNAME $HOME_DIR/.code-server
mkdir -p $HOME_DIR/.config
chown -R $USERNAME:$USERNAME $HOME_DIR/.config
mkdir -p $HOME_DIR/.local
chown -R $USERNAME:$USERNAME $HOME_DIR/.local

# ============================================================
# 2. Initialize workspace (clone task on first run)
# ============================================================
INIT_MARKER="/var/log/sandbox/.initialized"
if [ ! -f "$INIT_MARKER" ] && [ -n "$TASK_REPO" ]; then
    echo "Initializing workspace: TASK_REPO=$TASK_REPO TASK_FOLDER=$TASK_FOLDER" >> /var/log/sandbox/entrypoint.log
    sudo -u $USERNAME TASK_REPO="$TASK_REPO" TASK_FOLDER="$TASK_FOLDER" CANDIDATE_NAME="$CANDIDATE_NAME" bash /usr/lib/sandbox/startup.sh >> /var/log/sandbox/entrypoint.log 2>&1
    RESULT=$?
    echo "startup.sh exit code: $RESULT" >> /var/log/sandbox/entrypoint.log
    touch "$INIT_MARKER"
    chown $USERNAME:$USERNAME "$INIT_MARKER"
elif [ -f "$INIT_MARKER" ]; then
    echo "Workspace already initialized, skipping" >> /var/log/sandbox/entrypoint.log
fi

# ============================================================
# 3. Start file tracking (background, as root — invisible)
# ============================================================
/usr/lib/sandbox/agent-helper $HOME_DIR/workspace /var/log/sandbox &

# ============================================================
# 4. Record session start
# ============================================================
echo "start: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> /var/log/sandbox/sessions.log

# ============================================================
# 5. Generate SSH host keys if missing (first run)
# ============================================================
ssh-keygen -A 2>/dev/null

# ============================================================
# 6. Start SSH server
# ============================================================
/usr/sbin/sshd

# ============================================================
# 7. Start code-server (as coder user, foreground)
# ============================================================
export PASSWORD="$SANDBOX_PASSWORD"
exec sudo -u $USERNAME env PASSWORD="$SANDBOX_PASSWORD" /opt/code-server/bin/code-server \
    --auth password \
    --port 13337 \
    --host 0.0.0.0 \
    --user-data-dir $HOME_DIR/.code-server \
    --welcome-text "Enter your password to access the workspace." \
    $HOME_DIR/workspace
