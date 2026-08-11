#!/bin/zsh
# Daily work sync for 识图 / recognizeGraph
# - Append a dated worklog stub if missing
# - Commit local changes (if any)
# - Push to origin/main

set -euo pipefail

REPO_DIR="/Users/mac/Desktop/识图"
LOG_DIR="$REPO_DIR/docs/worklog"
TODAY="$(date +%Y-%m-%d)"
TIME="$(date +%H:%M:%S)"
LOG_FILE="$LOG_DIR/$TODAY.md"
RUN_LOG="$HOME/Library/Logs/shitu-daily-sync.log"

mkdir -p "$LOG_DIR" "$(dirname "$RUN_LOG")"
exec >>"$RUN_LOG" 2>&1
echo "===== $TODAY $TIME daily-sync start ====="

cd "$REPO_DIR"

# Load SSH key from macOS Keychain (non-interactive after first ssh-add)
ssh-add --apple-load-keychain 2>/dev/null || true

# Ensure worklog page for today
if [[ ! -f "$LOG_FILE" ]]; then
  cat > "$LOG_FILE" <<EOF
# 工作记录 $TODAY

> 自动生成于 $TIME。可继续在下方补充今日进展。

## 今日进展

- （待补充）

## 备注

-
EOF
fi

# Refresh remote tracking quietly; ignore network blips
git fetch origin main 2>/dev/null || true

# Stage everything except ignored files
git add -A

if git diff --cached --quiet; then
  echo "No local changes to commit."
else
  git commit -m "chore(daily): worklog and sync $TODAY"
  echo "Committed local changes."
fi

# Push if ahead of remote
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  AHEAD="$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)"
else
  git branch --set-upstream-to=origin/main main 2>/dev/null || true
  AHEAD=1
fi

if [[ "${AHEAD:-0}" != "0" ]]; then
  git push origin main
  echo "Pushed to origin/main."
else
  echo "Already up to date with origin/main."
fi

echo "===== $TODAY $TIME daily-sync done ====="
