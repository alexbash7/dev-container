#!/bin/bash
set -e

WORKSPACE_DIR="/home/coder/workspace"
TASK_REPO="${TASK_REPO:-}"
TASK_FOLDER="${TASK_FOLDER:-}"

if [ -z "$TASK_REPO" ]; then
    echo "No task repo specified"
    exit 0
fi

TMP_CLONE="/tmp/task-repo-$$"
git clone --depth 1 "$TASK_REPO" "$TMP_CLONE" 2>/dev/null || { echo "Failed to clone repo"; exit 1; }

if [ -n "$TASK_FOLDER" ] && [ -d "$TMP_CLONE/$TASK_FOLDER" ]; then
    cp -r "$TMP_CLONE/$TASK_FOLDER"/. "$WORKSPACE_DIR/" 2>/dev/null || true
elif [ -d "$TMP_CLONE" ]; then
    rsync -a --exclude='.git' "$TMP_CLONE/" "$WORKSPACE_DIR/" 2>/dev/null || true
fi

rm -rf "$TMP_CLONE"

# Init git for tracking
cd "$WORKSPACE_DIR"
git init -q
git config user.email "candidate@workspace.local"
git config user.name "candidate"
git add -A 2>/dev/null
git commit -q -m "initial: task files" --allow-empty 2>/dev/null

echo "Workspace initialized"
