# TTS 音频生成与缓存说明

> 用途：说清楚「详情页语音从哪来、缓存在哪、何时计费、以后怎么做服务端缓存」。  
> 更新：有行为变更时请同步改本文件，并在 `docs/工作记录.md` 当日条目留一句索引。

---

## 1. 两条播报链路（详情页）

| 入口 | 播报稿 | 是否记学习 | 接口 |
|------|--------|------------|------|
| 名称旁喇叭（中英点读） | `中文名。English。`（无英文则仅中文） | 否 | 先 `GET /v1/name-en`，再 `POST /v1/tts`（`text`=完整稿） |
| 底栏「听一听介绍」 | 名字 + 简介（`one_liner`） | 是（登录且非历史入口时） | `POST /v1/tts`（`name`+`one_liner`） |

- **合成引擎**：百度智能云 **短文本在线合成**（`text2audio`），响应体直接是 MP3 字节，**不是**「24 小时过期的下载链接」。  
- **24 小时时效**：多见于百度**长文本/异步**产品的临时 URL；与当前短文本接口无关。App 拿到字节后可自行长期保存。  
- **音色**：均带 `voice_profile`=`a|b|c`（本地偏好）。

英文名来源（与音频缓存无关，但是点读稿的一部分）：

1. 内置词表 `server/resources/name_en/zh_en_map.json`
2. 学习词表 `server/data/name_en/zh_en_learned.json`（机翻成功回填，gitignore）
3. 百度文本翻译-通用版兜底 → 写入学习词表

---

## 2. 当前缓存策略（已实现）

### 2.1 App 本地（音频）

| 类型 | 存放 | 复用条件 | 生命周期 / 清理 |
|------|------|----------|-----------------|
| 介绍 MP3 | `getTemporaryDirectory()` 临时文件 + 详情页 State（`_audioFile`） | 同详情页实例 + 同 `voice_profile` + `_audioKind==intro` | **离开详情页**即丢 State；临时文件无专用清理，靠系统清 tmp / 用户清 App 缓存 |
| 名字点读 MP3 | 同上临时目录 + State（`_nameAudioFile` / `_nameAudioProfile` / `_nameAudioScript`） | 同详情页 + 同偏好 + **同播报稿字符串** | 同上；与介绍缓存**分开**，互不覆盖 |

要点：

- **同页多次点名字喇叭**：首次合成并计费，之后本地重播，**不再打百度 TTS**。  
- **换语音偏好**或离开再进详情：缓存失效，会再次合成。  
- **服务器不存 MP3**：`POST /v1/tts` 每次都向百度要音频再转给客户端（除非命中 App 侧缓存而不发请求）。

### 2.2 服务器（仅文字，非音频）

| 类型 | 路径 | 容量 | 清理 |
|------|------|------|------|
| 机翻学习词表 | `server/data/name_en/zh_en_learned.json` | 极小（纯 JSON） | 无自动过期；可手工删文件 |

---

## 3. 计费直觉（短文本 TTS）

- 费用发生在 **调用百度合成接口成功返回音频** 时。  
- App 用本地已缓存的临时 MP3 重播 → **不产生新的 TTS 调用**。  
- 英文「学习词表」只省 **翻译** 次数，不省 TTS；TTS 仍看是否重新合成。

---

## 4. 后续方案：服务器缓存 MP3（未实现）

目标：跨用户、跨会话复用同一段合成结果，进一步降本、加快首播。

### 4.1 建议 Key

```
sha256( voice_profile + "\n" + speak_script_utf8 )
```

或更可读：

```
{profile}/{hash16}.mp3
```

`speak_script` 必须是最终送入百度的完整 `tex` 文稿（介绍稿或「中文。English。」）。

### 4.2 存储

- 开发：本地目录如 `server/data/tts_cache/`（已在 `server/data/` gitignore 下）。  
- 上云：对象存储（OSS/COS/S3）+ 可选 CDN；数据库只存 `key → object_key / size / created_at / last_access`。

### 4.3 HTTP 行为（草图）

1. `POST /v1/tts` 算出 cache key。  
2. 命中且未过期 → 直接 `audio/mpeg` 回文件（或 302 到签名 URL）。  
3. 未命中 → 调百度 → 写入缓存 → 返回。  
4. 响应头可加：`X-TTS-Cache: HIT|MISS`，便于联调。

### 4.4 容量与清理（上云必做）

| 策略 | 建议起点 |
|------|----------|
| TTL | 7～30 天（按 `last_access` 或 `created_at`） |
| 总容量上限 | 如 5～20 GB，超限按 LRU 删 |
| 单文件 | 名字点读通常数十 KB；介绍可达数百 KB～数 MB（长百科分段拼接） |
| 粗算 | 1 万条 × 50KB ≈ 500MB；百万级必须上对象存储 + 淘汰 |

不必一上云就开音频缓存；流量/费用上去后再做。英文学习词表继续用 JSON/DB 即可，与 MP3 缓存解耦。

### 4.5 实现时注意

- 密钥仍只在服务端；缓存文件勿公开列目录。  
- 同一文稿不同 `voice_profile` 必须分 key。  
- 百度短文本改参（spd/per/emo）后要变 key 或整盘失效。  
- 合规：缓存的是合成音，不是用户原声；仍需遵守百度商用条款。

### 4.6 推荐落地顺序

1. App 同页缓存（名字 + 介绍）— **已做**  
2. 服务端内存/磁盘 MP3 缓存 + `X-TTS-Cache`  
3. 迁对象存储 + TTL/LRU 指标（命中率、体积）

---

## 5. 相关代码索引

| 位置 | 说明 |
|------|------|
| `app/lib/screens/detail_screen.dart` | 介绍/名字点读、本页 MP3 缓存 |
| `app/lib/services/tts_api.dart` | 请求 `/v1/tts`，写入临时 mp3 |
| `app/lib/services/name_en_api.dart` | 请求 `/v1/name-en` |
| `server/app/baidu/tts.py` | 百度短文本合成、分段拼接 |
| `server/app/routers/tts.py` | `POST /v1/tts` |
| `server/app/services/name_en.py` | 词表 + 学习回填 + 机翻 |
| `server/resources/name_en/` | 内置中英词表与署名说明 |

---

## 6. 变更记录

| 日期 | 说明 |
|------|------|
| 2026-08-14 | 初稿：现状（App 临时缓存、无服务端 MP3）+ 名字点读同页只合成一次 + 服务端缓存方案备忘 |
