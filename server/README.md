# 识图后端（FastAPI）

## 本地启动

```bash
cd server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# 编辑 .env，填入 BAIDU_API_KEY 与 BAIDU_SECRET_KEY

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

- 健康检查：http://127.0.0.1:8000/health  
- 接口文档：http://127.0.0.1:8000/docs  

## 识别接口

`POST /v1/recognize`（multipart）

| 字段 | 说明 |
|------|------|
| `category` | `animal` / `plant` / `transport` |
| `image` | 图片文件 |

```bash
curl -X POST "http://127.0.0.1:8000/v1/recognize" \
  -F "category=animal" \
  -F "image=@/path/to/cat.jpg"
```

## 登录接口（MVP）

暂未对接短信运营商：验证码在服务端本地生成，**响应里明文返回 `code`**，供 App Toast 演示。接短信后应删除该字段。

| 接口 | 说明 |
|------|------|
| `POST /v1/auth/sms-code` | JSON `{"phone"}` → `code` / `expires_in`(300) / `resend_after`(60) |
| `POST /v1/auth/login` | JSON `{"phone","code"}` → `token` / 用户资料；用户写入数据库 |
| `POST /v1/auth/logout` | Bearer token，作废会话 |
| `GET /v1/me` | Bearer → 昵称 / 学习次数 / 等级 / 头像字段 |

手机号校验：大陆 `1[3-9]` + 9 位数字。验证码仍在内存；**用户与会话持久化在数据库**。

## 学习历史

| 接口 | 说明 |
|------|------|
| `GET /v1/history/months` | 仅返回有记录的月份（无空月） |
| `GET /v1/history?month=YYYY-MM&page=&page_size=` | 按月分页 |
| `POST /v1/history` | multipart：名称等字段 + 可选 `thumb` 用户图缩略图 |

等级：按累计学习次数进阶（前期易升、后期变难），见 `app/auth/levels.py`；接口返回 `level` / `learns_to_next` / `level_hint`。缩略图：`/media/thumbs/...`

## 语音播报（详情页）

方案：**短文本 + 实时 + 非流式 + 百度云**。超 1024 GBK 字节时服务端按标点分段合成，再拼接为一条 MP3。

| 接口 | 说明 |
|------|------|
| `POST /v1/tts` | JSON：`name` + `one_liner`（或 `text`）+ 可选 `voice_profile`=`a|b|c` → `audio/mpeg` |

偏好映射：`a` 度小童偏慢+活泼；`b` 度博文中速；`c` 度小美中速（音量/音调均为 5）。控制台需开通 **短文本在线合成**。

```bash
curl -X POST "http://127.0.0.1:8000/v1/tts" \
  -H "Content-Type: application/json" \
  -d '{"name":"葫芦","one_liner":"一种常见的植物果实。"}' \
  --output /tmp/shitu-tts.mp3
```

## 数据库

- 默认 **SQLite**：`server/data/shitu.db`（方便本机；`server/data/` 已 gitignore）
- 上云改环境变量即可，例如：
  `DATABASE_URL=postgresql+psycopg://user:pass@host:5432/shitu`
  （需自行安装对应驱动；模型用 SQLAlchemy，便于迁移）
