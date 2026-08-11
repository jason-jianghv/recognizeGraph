#!/bin/zsh
# Daily work sync for 识图 / recognizeGraph
# - 仅当「当天项目有改动」时更新 docs/工作记录.md 的 Git 自动摘要
# - 有未提交改动则 commit，并 push 到 origin/main

set -euo pipefail

REPO_DIR="/Users/mac/Desktop/识图"
WORKLOG="$REPO_DIR/docs/工作记录.md"
TODAY="$(date +%Y-%m-%d)"
TIME="$(date +%H:%M:%S)"
SINCE="$TODAY 00:00:00"
RUN_LOG="$HOME/Library/Logs/shitu-daily-sync.log"

mkdir -p "$(dirname "$RUN_LOG")" "$REPO_DIR/docs"
exec >>"$RUN_LOG" 2>&1
echo "===== $TODAY $TIME daily-sync start ====="

cd "$REPO_DIR"
ssh-add --apple-load-keychain 2>/dev/null || true

git fetch origin main 2>/dev/null || true

# ---- 是否「当天有项目改动」----
# 1) 今天有过提交  2) 工作区相对 HEAD 有改动  3) 暂存区有改动
HAS_TODAY_COMMIT=0
if git log --since="$SINCE" --oneline --no-merges 2>/dev/null | grep -q .; then
  HAS_TODAY_COMMIT=1
fi

HAS_DIRTY=0
if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  HAS_DIRTY=1
fi

if [[ "$HAS_TODAY_COMMIT" -eq 0 && "$HAS_DIRTY" -eq 0 ]]; then
  echo "No project changes today. Skip worklog update / push."
  echo "===== $TODAY $TIME daily-sync done (noop) ====="
  exit 0
fi

echo "Detected changes today (commits=$HAS_TODAY_COMMIT dirty=$HAS_DIRTY). Updating worklog."

# ---- 收集 Git 摘要 ----
COMMITS="$(git log --since="$SINCE" --pretty=format:'- %h %s' --no-merges 2>/dev/null || true)"
if [[ -z "${COMMITS// }" ]]; then
  COMMITS="- （今日尚无提交，以下为未提交改动）"
fi

FILES="$(
  {
    git log --since="$SINCE" --name-only --pretty=format: --no-merges 2>/dev/null
    git diff --name-only HEAD 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  } | sed '/^$/d' | sort -u | sed 's/^/- /'
)"
if [[ -z "${FILES// }" ]]; then
  FILES="- （无文件列表）"
fi

STAT="$(git diff --stat HEAD 2>/dev/null || true)"
if [[ -z "${STAT// }" ]]; then
  STAT="$(git show --stat --oneline --no-patch $(git log --since="$SINCE" --pretty=%H --no-merges -1 2>/dev/null) 2>/dev/null || true)"
fi

AUTO_BLOCK=$(cat <<EOF
#### 当日自动摘要（Git）

> 自动刷新于 $TIME。上方「今日做了什么 / 踩坑 / 决策」请在协作时由人工或 Cursor 补充，本段只反映 Git 事实。

**提交**

$COMMITS

**涉及文件**

$FILES
EOF
)

# ---- 确保工作记录主文件存在 ----
if [[ ! -f "$WORKLOG" ]]; then
  cat > "$WORKLOG" <<EOF
# 识图 · 工作记录

## 按日记录

<!-- DAILY_ENTRIES_START -->
<!-- DAILY_ENTRIES_END -->
EOF
fi

python3 - "$WORKLOG" "$TODAY" "$AUTO_BLOCK" <<'PY'
import pathlib, re, sys

path = pathlib.Path(sys.argv[1])
today = sys.argv[2]
auto_block = sys.argv[3]
text = path.read_text(encoding="utf-8")

day_header = f"### {today}"
new_day = f"""### {today}

#### 今日做了什么

- （请在协作中补充；下方为 Git 自动摘要）

#### 踩坑与解决

- （无则写「无」；有则同步到文首「踩坑速查」）

#### 决策与取舍

- （无则写「无」）

#### 待继续

- （无则写「无」）

{auto_block}
"""

start = "<!-- DAILY_ENTRIES_START -->"
end = "<!-- DAILY_ENTRIES_END -->"
if start not in text or end not in text:
    text = text.rstrip() + f"\n\n{start}\n{new_day}\n{end}\n"
    path.write_text(text, encoding="utf-8")
    print("Inserted daily markers + today entry")
    raise SystemExit(0)

pre, rest = text.split(start, 1)
mid, post = rest.split(end, 1)

# Find existing ### today section inside mid
pattern = re.compile(
    rf"(### {re.escape(today)}\n)(.*?)(?=\n### |\Z)",
    re.S,
)
m = pattern.search(mid)
if not m:
    mid = "\n" + new_day + "\n" + mid.lstrip("\n")
    print(f"Created entry for {today}")
else:
    body = m.group(0)
    # Replace only the auto summary subsection; keep human sections
    auto_pat = re.compile(
        r"#### 当日自动摘要（Git）\n.*?(?=\n#### |\n### |\Z)",
        re.S,
    )
    if auto_pat.search(body):
        body2 = auto_pat.sub(auto_block.strip() + "\n", body, count=1)
    else:
        body2 = body.rstrip() + "\n\n" + auto_block.strip() + "\n"
    mid = mid[: m.start()] + body2 + mid[m.end() :]
    print(f"Refreshed Git auto summary for {today}")

path.write_text(pre + start + mid + end + post, encoding="utf-8")
PY

# ---- commit & push ----
git add -A

if git diff --cached --quiet; then
  echo "Nothing new to commit after worklog update."
else
  git commit -m "docs(worklog): daily record $TODAY"
  echo "Committed."
fi

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
