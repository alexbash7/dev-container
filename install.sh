#!/bin/bash
# ============================================================
# Install dev-sandbox on the server
# Run once on the target machine
# ============================================================

set -e

INSTALL_DIR="/opt/dev-sandbox"

echo "Installing dev-sandbox to $INSTALL_DIR..."

# Create directories
mkdir -p "$INSTALL_DIR/data"

# Copy files
cp -r docker scripts "$INSTALL_DIR/"
cp README.md "$INSTALL_DIR/"

# Make scripts executable
chmod +x "$INSTALL_DIR/scripts/"*.sh
chmod +x "$INSTALL_DIR/docker/"*.sh

# Install container-shell
cp "$INSTALL_DIR/scripts/container-shell.sh" /usr/local/bin/sandbox-shell
chmod +x /usr/local/bin/sandbox-shell

# Add sandbox-shell to allowed shells
if ! grep -q sandbox-shell /etc/shells; then
    echo "/usr/local/bin/sandbox-shell" >> /etc/shells
fi

# Build Docker image
echo "Building Docker image..."
docker build -t dev-sandbox:latest "$INSTALL_DIR/docker/"

# Setup cron jobs
CRON_FILE="/etc/cron.d/dev-sandbox"
cat > "$CRON_FILE" << 'CRON'
# Auto-stop idle containers every 5 minutes
*/5 * * * * root /opt/dev-sandbox/scripts/auto-stop.sh >> /var/log/sandbox-autostop.log 2>&1

# Auto-cleanup expired containers every hour
0 * * * * root /opt/dev-sandbox/scripts/auto-cleanup.sh >> /var/log/sandbox-cleanup.log 2>&1
CRON
chmod 644 "$CRON_FILE"

echo ""
echo "=== Installation complete ==="
echo ""
echo "Usage:"
echo "  Create workspace:  $INSTALL_DIR/scripts/create-workspace.sh --name <name> --task-folder <folder>"
echo "  Delete workspace:  $INSTALL_DIR/scripts/delete-workspace.sh <name>"
echo ""
echo "Note: Ensure wildcard SSL cert for *.code.trafflume.com exists"
echo "Note: Ensure nginx has lua module (libnginx-mod-http-lua) for browser auto-start"
