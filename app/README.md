# 识图 Flutter 客户端

对照 Figma「童趣」稿与 `PRD.md` 实现的 MVP。

## 已实现

- 开屏页
- 探索（三类推荐 + 更多列表）
- 空间（未登录 / 已登录示意）+ 登录 / 设置 / 关于我
- 拍照（相册/相机 + 三类分类）→ 调后端识别 → 结果横滑 → 详情

## 运行前

1. 启动后端：`cd server && source .venv/bin/activate && uvicorn app.main:app --reload --port 8000`
2. 安装 Flutter（本机已克隆到 `~/development/flutter`，可把该路径加入 PATH）
3. 真机调试时，把 `lib/services/recognize_api.dart` 里的 baseUrl 改成电脑局域网 IP，例如 `http://192.168.1.8:8000`

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
cd app
flutter pub get
flutter run
```
