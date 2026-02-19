# Dev Sandbox

Lightweight Docker-based test environments for developer candidates.

## Features
- VS Code in browser (code-server)
- SSH access (VS Code Desktop / terminal)
- Auto-start on connect (SSH or browser)
- Auto-stop after 15 min inactivity
- Auto-delete after 72 hours
- Invisible file tracking (git auto-commit)
- Bash history audit
- Task cloning from git repo

## Usage

```bash
# Create workspace
./scripts/create-workspace.sh --name florence-c --task-folder dev1 --password xK9mT2

# Delete workspace
./scripts/delete-workspace.sh florence-c

# Auto-stop inactive (cron every 5 min)
./scripts/auto-stop.sh

# Auto-cleanup expired (cron every hour)
./scripts/auto-cleanup.sh
```

## Candidate gets

```
Browser IDE: https://florence-c.code.trafflume.com
SSH: ssh florence-c@code.trafflume.com -p 34521
Password: xK9mT2
```

## Architecture

```
Candidate
  ├── SSH (VS Code / Terminal) → sshd on host → container-shell → docker start → docker exec
  └── Browser → nginx → auto-start → proxy to code-server
```

## Cron setup

```bash
# Auto-stop idle containers (every 5 min)
*/5 * * * * /opt/dev-sandbox/scripts/auto-stop.sh >> /var/log/sandbox-autostop.log 2>&1

# Auto-delete expired containers (every hour)
0 * * * * /opt/dev-sandbox/scripts/auto-cleanup.sh >> /var/log/sandbox-cleanup.log 2>&1
```
