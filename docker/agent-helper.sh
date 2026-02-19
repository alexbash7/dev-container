#!/bin/bash
# File change tracker — runs as root, invisible to candidate
# Records all file changes and auto-commits to git

WORKSPACE_DIR="$1"
LOG_DIR="$2"

[ -z "$WORKSPACE_DIR" ] || [ -z "$LOG_DIR" ] && exit 1

sleep 3

cd "$WORKSPACE_DIR" || exit 1

exec inotifywait -m -r "$WORKSPACE_DIR" \
    --exclude '\.git|\.code-server|node_modules|__pycache__' \
    -e modify,create,delete,move \
    --format '%T|%e|%w%f' \
    --timefmt '%Y-%m-%d %H:%M:%S' 2>/dev/null |
while IFS='|' read -r ts event file; do
    echo "$ts|$event|$file" >> "$LOG_DIR/file_changes.log"
    sleep 2
    cd "$WORKSPACE_DIR" || continue
    git add -A 2>/dev/null
    git commit -q -m "$ts $event $(basename "$file")" --allow-empty 2>/dev/null
done
