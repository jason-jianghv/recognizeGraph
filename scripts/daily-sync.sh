#!/bin/zsh
# Daily work sync for 识图 / recognizeGraph
# - 仅当「当天项目有改动」时更新 docs/工作记录.md 的 Git 自动摘要
# - 有未提交改动则 commit，并 push 到 origin/main
#
# LaunchAgent 注意：
# 1) 入口必须是 ASCII 路径（~/bin/shitu-daily-sync.sh），勿让 launchd 直接 exec 中文路径脚本
# 2) 仓库若在「桌面/文稿/下载」，须给 /bin/zsh 开「完全磁盘访问权限」，否则 git 会
#    Operation not permitted（定时任务看起来像没跑）
# 3) 改本文件后请同步：cp scripts/daily-sync.sh ~/bin/shitu-daily-impl.sh

set -euo pipefail

REPO_DIR="/Users/mac/Desktop/识图"
WORKLOG="$REPO_DIR/docs/工作记录.md"
TODAY="$(date +%Y-%m-%d)"
TIME="$(date +%H:%M:%S)"
SINCE="$TODAY 00:00:00"
RUN_LOG="$HOME/Library/Logs/shitu-daily-sync.log"
GIT=(git -C "$REPO_DIR")

# 不要 cd 进桌面仓库：LaunchAgent 在受保护目录里 cwd 会直接 Operation not permitted
cd "$HOME"

mkdir -p "$(dirname "$RUN_LOG")"
# docs 目录若尚不存在，由有权限的交互环境先建好；此处失败只记日志
mkdir -p "$REPO_DIR/docs" 2>/dev/null || true

exec >>"$RUN_LOG" 2>&1
echo "===== $TODAY $TIME daily-sync start ====="

if ! "${GIT[@]}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: cannot access git repo at $REPO_DIR"
  echo "If the repo is on Desktop, grant Full Disk Access to /bin/zsh:"
  echo "  系统设置 → 隐私与安全性 → 完全磁盘访问权限 → 添加 /bin/zsh"
  echo "===== $TODAY $TIME daily-sync failed (repo inaccessible) ====="
  exit 1
fi

ssh-add --apple-load-keychain 2>/dev/null || true

"${GIT[@]}" fetch origin main 2>/dev/null || true

# ---- 是否「当天有项目改动」----
HAS_TODAY_COMMIT=0
if "${GIT[@]}" log --since="$SINCE" --oneline --no-merges 2>/dev/null | grep -q .; then
  HAS_TODAY_COMMIT=1
fi

HAS_DIRTY=0
if ! "${GIT[@]}" diff --quiet || ! "${GIT[@]}" diff --cached --quiet || [[ -n "$("${GIT[@]}" ls-files --others --exclude-standard)" ]]; then
  HAS_DIRTY=1
fi

if [[ "$HAS_TODAY_COMMIT" -eq 0 && "$HAS_DIRTY" -eq 0 ]]; then
  echo "No project changes today. Skip worklog update / push."
  echo "===== $TODAY $TIME daily-sync done (noop) ====="
  exit 0
fi

echo "Detected changes today (commits=$HAS_TODAY_COMMIT dirty=$HAS_DIRTY). Updating worklog."

# ---- 收集 Git 摘要 ----
COMMITS="$("${GIT[@]}" log --since="$SINCE" --pretty=format:'- %h %s' --no-merges 2>/dev/null || true)"
if [[ -z "${COMMITS// }" ]]; then
  COMMITS="- （今日尚无提交，以下为未提交改动）"
fi

FILES="$(
  {
    "${GIT[@]}" -c core.quotepath=false log --since="$SINCE" --name-only --pretty=format: --no-merges 2>/dev/null
    "${GIT[@]}" -c core.quotepath=false diff --name-only HEAD 2>/dev/null
    "${GIT[@]}" -c core.quotepath=false ls-files --others --exclude-standard 2>/dev/null
  } | sed '/^$/d' | sort -u | sed 's/^/- /'
)"
if [[ -z "${FILES// }" ]]; then
  FILES="- （无文件列表）"
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
"${GIT[@]}" add -A

if "${GIT[@]}" diff --cached --quiet; then
  echo "Nothing new to commit after worklog update."
else
  "${GIT[@]}" commit -m "docs(worklog): daily record $TODAY"
  echo "Committed."
fi

if "${GIT[@]}" rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  AHEAD="$("${GIT[@]}" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)"
else
  "${GIT[@]}" branch --set-upstream-to=origin/main main 2>/dev/null || true
  AHEAD=1
fi

if [[ "${AHEAD:-0}" != "0" ]]; then
  "${GIT[@]}" push origin main
  echo "Pushed to origin/main."
else
  echo "Already up to date with origin/main."
fi

echo "===== $TODAY $TIME daily-sync done ====="
