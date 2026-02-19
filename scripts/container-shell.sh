#!/bin/bash
# Login shell for sandbox host users
# Auto-starts the container and exec's into it
# Install to: /usr/local/bin/sandbox-shell

CONTAINER="sandbox-$(whoami)"

# Start container if not running
STATE=$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)
if [ "$STATE" != "true" ]; then
    echo "Starting workspace..."
    docker start "$CONTAINER" >/dev/null 2>&1
    # Wait for SSH and services to be ready
    for i in $(seq 1 15); do
        docker exec "$CONTAINER" pgrep sshd >/dev/null 2>&1 && break
        sleep 0.5
    done
fi

# Exec into container as coder user
exec docker exec -it -u coder -w /home/coder/workspace "$CONTAINER" /bin/bash -l
