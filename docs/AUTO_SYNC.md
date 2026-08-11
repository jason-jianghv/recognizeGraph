# 自动同步说明

## SSH 口令（只需做一次）

在终端执行：

```bash
ssh-add --apple-use-keychain ~/.ssh/id_rsa
```

输入一次私钥口令后，会写入 macOS「钥匙串」，之后 `git push` / 每日自动同步一般不再反复询问。

## 每日自动任务

- 脚本：`scripts/daily-sync.sh`
- 计划：每天 **18:00**（可通过 LaunchAgent 修改）
- 行为：
  1. 若当天没有工作记录，则创建 `docs/worklog/YYYY-MM-DD.md`
  2. 有未提交改动则自动 commit
  3. `git push origin main`
- 运行日志：`~/Library/Logs/shitu-daily-sync.log`

### 改时间

编辑 `~/Library/LaunchAgents/com.shitu.daily-sync.plist` 里的 `Hour` / `Minute`，然后：

```bash
launchctl bootout "gui/$(id -u)/com.shitu.daily-sync"
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.shitu.daily-sync.plist
```

### 手动试跑

```bash
"/Users/mac/Desktop/识图/scripts/daily-sync.sh"
```
