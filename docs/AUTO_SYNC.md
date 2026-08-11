# 自动同步与工作记录

## 工作记录主文件

- 路径：`docs/工作记录.md`
- 包含：阶段里程碑、踩坑速查、常用命令、按日记录
- **有改动才记**：定时任务检测到「当日有提交或未提交改动」才会刷新当日 Git 摘要

## SSH 口令（一次）

```bash
ssh-add --apple-use-keychain ~/.ssh/id_rsa
```

## 每日自动任务（与 Cursor 无关）

- 时间：每天 **18:00**
- 脚本：`scripts/daily-sync.sh`
- LaunchAgent：`~/Library/LaunchAgents/com.shitu.daily-sync.plist`
- 日志：`~/Library/Logs/shitu-daily-sync.log`

流程：

1. 判断当天是否有项目改动（无则直接退出）
2. 更新 `docs/工作记录.md` 中当日「当日自动摘要（Git）」
3. `git commit`（如有变更）并 `git push origin main`

## 手动试跑

```bash
"/Users/mac/Desktop/识图/scripts/daily-sync.sh"
```

## 改时间

编辑 plist 中 `Hour` / `Minute` 后：

```bash
launchctl bootout "gui/$(id -u)/com.shitu.daily-sync"
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.shitu.daily-sync.plist
```
