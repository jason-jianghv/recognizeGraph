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

## 名字中英点读

详情页名称旁喇叭：词表优先，未命中再机翻（百度智能云文本翻译）。

| 接口 | 说明 |
|------|------|
| `GET /v1/name-en?name=` | → `name_zh` / `name_en` / `source`(`lexicon\|translate\|none`) / `speak` |
| `POST /v1/name-en` | JSON 同上 |

词表：`server/resources/name_en/`（约 1200 动物 + 1200 植物；CC-BY 衍生需署名 Tropicals.cn）。重建见 `scripts/build_name_en_lexicon.py`。机翻需在同一应用开通 **文本翻译-通用版**。

机翻成功后会写入本地学习词表 `server/data/name_en/zh_en_learned.json`（gitignore），下次同一中文名直接命中，不再重复调用翻译。

## 数据库

- 默认 **SQLite**：`server/data/shitu.db`（方便本机；`server/data/` 已 gitignore）
- 上云改环境变量即可，例如：
  `DATABASE_URL=postgresql+psycopg://user:pass@host:5432/shitu`
  （需自行安装对应驱动；模型用 SQLAlchemy，便于迁移）

### 物种目录 `catalog_species`

| 能力 | 说明 |
|------|------|
| 唯一性 | `(category, name)` 唯一；`name` 去首尾空白并合并中间空白 |
| 种子 | 启动时仅写入词表 **seed / transport_seed**（常规）；**暂不新加** tropials 生僻种；已入库 tropicals **不删**，标 `is_common=0` |
| 回填 | `POST /v1/recognize` 候选须**同时有图片 + 简介**才 upsert；识别条目 `is_common=1` |
| 探索列表 | `GET /v1/catalog?common_only=true`（默认）只返回常规；`false` 可含生僻 |
| 近义去重 | `catalog_aliases.py`：小狗狗→小狗 等；别名行/圆仔等探索隐藏；识别写入规范名 |
| 配图国内可达 | 维基 `upload.wikimedia.org` 国内不可用；`scripts/cache_catalog_images.py` 拉到 `data/catalog_images/`；`GET /v1/catalog` 返回 `/media/catalog_images/{id}.jpg` |
| 简介补齐 | 缺简介/配图时用中文维基（可再试英文）；默认只补常规：`scripts/backfill_catalog_desc.py --common-only`；全量加 `--all` |

```bash
# 手动补种子 / 标记常规
cd server && source .venv/bin/activate
python ../scripts/seed_catalog.py

# 批量补简介
PYTHONUNBUFFERED=1 python -u ../scripts/backfill_catalog_desc.py --batch 20 --sleep 1.5

curl "http://127.0.0.1:8000/v1/catalog?category=animal&page_size=20"
curl "http://127.0.0.1:8000/v1/catalog?category=animal&common_only=false&page_size=20"
```
