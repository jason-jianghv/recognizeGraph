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
