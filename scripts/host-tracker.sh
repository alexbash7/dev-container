#!/bin/bash
# Host-level file tracker for dev-sandbox
# Runs on HOST, monitors workspace volumes via inotifywait
# Invisible from inside containers
#
# Usage: host-tracker.sh <sandbox-name>
# Example: host-tracker.sh florence-c

set -e

NAME="$1"
[ -z "$NAME" ] && echo "Usage: $0 <sandbox-name>" && exit 1

BASE_DIR="/opt/dev-sandbox/data/$NAME"
WORKSPACE="$BASE_DIR/workspace"
LOGS="$BASE_DIR/logs"
SHADOW_GIT="$BASE_DIR/shadow-git"

# Ensure directories exist
mkdir -p "$LOGS" "$SHADOW_GIT"

# Initialize shadow git if needed
if [ ! -d "$SHADOW_GIT/refs" ]; then
    git init --bare "$SHADOW_GIT" >/dev/null 2>&1
    # Initial commit
    GIT="git --git-dir=$SHADOW_GIT --work-tree=$WORKSPACE"
    $GIT add -A 2>/dev/null
    $GIT commit -q -m "initial: workspace created" --allow-empty 2>/dev/null || true
fi

GIT="git --git-dir=$SHADOW_GIT --work-tree=$WORKSPACE"

echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] Host tracker started for $NAME (PID $$)" >> "$LOGS/tracker.log"

# Debounce: collect changes for 2 seconds, then commit once
PENDING=false
LAST_COMMIT=0

commit_changes() {
    local now=$(date +%s)
    # Debounce: don't commit more than once per 2 seconds
    if [ $((now - LAST_COMMIT)) -lt 2 ]; then
        return
    fi

    cd "$WORKSPACE" || return

    # Check if there are actual changes
    if $GIT diff --quiet 2>/dev/null && $GIT diff --cached --quiet 2>/dev/null && [ -z "$($GIT ls-files --others --exclude-standard 2>/dev/null)" ]; then
        return
    fi

    # Get diff stats before committing
    STATS=$($GIT diff --shortstat 2>/dev/null || echo "")

    $GIT add -A 2>/dev/null
    $GIT commit -q -m "auto: $(date -u '+%Y-%m-%d %H:%M:%S') $STATS" 2>/dev/null || true

    LAST_COMMIT=$now
    PENDING=false
}

# Monitor workspace with inotifywait
inotifywait -m -r "$WORKSPACE" \
    --exclude '\.git|\.code-server|node_modules|__pycache__|\.cache' \
    -e modify,create,delete,move \
    --format '%T|%e|%w%f' \
    --timefmt '%Y-%m-%d %H:%M:%S' 2>/dev/null |
while IFS='|' read -r ts event filepath; do
    # Get relative path
    relpath="${filepath#$WORKSPACE/}"
    
    # Get line count info for the file
    lines_info=""
    if [ -f "$filepath" ] && [[ "$event" == *"MODIFY"* || "$event" == *"CREATE"* ]]; then
        total_lines=$(wc -l < "$filepath" 2>/dev/null || echo "0")
        
        # Get diff stats from shadow git
        diff_stats=$($GIT diff --numstat -- "$relpath" 2>/dev/null | awk '{print "+"$1"-"$2}' || echo "")
        
        if [ -n "$diff_stats" ]; then
            lines_info="|${diff_stats}|${total_lines} lines"
        else
            lines_info="|+new|${total_lines} lines"
        fi
    elif [[ "$event" == *"DELETE"* ]]; then
        lines_info="|deleted|0 lines"
    fi

    # Write to file changes log
    echo "${ts}|${event}|${relpath}${lines_info}" >> "$LOGS/file_changes.log"

    # Schedule git commit (debounced)
    PENDING=true
    commit_changes
done
