# 识图

面向小朋友的拍照识物学习 App。

## 技术栈（已拍板）

| 层 | 选型 |
|----|------|
| 客户端 | Flutter（iOS / Android） |
| 后端 | Python + FastAPI |
| 识别 | 百度智能云图像识别 |

## 文档

- 产品需求：`PRD.md`
- 百度识图实施计划：`docs/实施计划-百度识图.md`
- 工作记录：`docs/工作记录.md`
- 后端说明：`server/README.md`

## 后端快速启动

```bash
cd server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # 填入百度 API Key / Secret Key
uvicorn app.main:app --reload --port 8000
```

打开 http://127.0.0.1:8000/docs 可调试识别接口。

## Flutter 客户端

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
cd app
flutter pub get
flutter run
```

详见 `app/README.md`。
