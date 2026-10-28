# 交接文档 · 1.0.96（Build 97）

- 日期：2026-10-29
- 分支：`codex/swift-v2-lifetime-reader`（远端）/ `codex/reader-feedback-fixes`（本地）
- 基线：1.0.95 可修清单（46 引擎可修 / 56 天花板）
- 本轮目标：落地可修清单、补齐「书源登录」链路、把书源修复写回源库

## 1. 编译与测试证据

| 项 | 结果 |
|---|---|
| `ec1ee5c` Unsigned IPA | **success**（run 40730911419，含 JS 错误上浮、登录中心、JSON 单字段 `||`） |
| `b56b853` / `1f24ad7` / `3dbf379` | 被后续提交顶掉（macOS runner 容量 cancelled），最新构建排队中 |
| 单元测试 | `ec1ee5c` 的 Unsigned IPA 工作流包含 `xcodebuild test`，通过后才会出包 |

> 结论：`f7dd81a`→`ec1ee5c` 的引擎改动已通过一次完整编译+测试。1.0.96 只是在其上追加 cookie 域匹配与版本号，待最新 run 出包。

## 2. 本轮代码改动

| 提交 | 内容 | 影响 |
|---|---|---|
| `1f24ad7` | 源库：得奇搜索/目录重建、QQ浏览器绕开 bodyJs、上游失效源标注 | 见 §3 |
| `b56b853` | `SourceCookieStore` 按 RFC 6265 做父域匹配 | 登录 cookie 在 `example.com` 登录后能带到 `www/m` 子域，修复「登录成功但仍 401」 |
| `3dbf379` | 得奇搜索规则改为 jsoup CSS 子集（`meta[property=...]`、`.bookname a`） | 降低引擎解析差异风险 |

cookie 匹配新增两条回归测试：
- `testCookieSetOnParentDomainReachesSubdomain`
- `testCookieStoredOnSubdomainAlsoServesThatSubdomain`

## 3. 书源修复（写入 `docs/sources/shareBookSource11-fixed-1.0.95.json`）

### 3.1 已按实测重建

**得奇小说网（https://www.deqixss.com）**

- 实测：`GET /modules/article/search.php?searchkey=斗破苍穹` → 200，167,659 字节，唯一命中时直接返回详情页（含 `#list-chapterAll` 全部章节）
- 搜索：`/modules/article/search.php?searchkey={{key}}`（UTF-8，无需 charset 选项）
- 列表：`@css:.bookbox||@css:html`（列表页多结果 / 详情页单结果两种形态）
- 字段：`h1.booktitle`、`meta[property=og:novel:author]`、`meta[property=og:url]`、`meta[property=og:image]`、`meta[property=og:description]`、`meta[property=og:novel:latest_chapter_name]`
- 目录：`@css:#list-chapterAll dd a` + `@text` / `@href`
- 正文：站点用 `chapter.js.php` + `yuedu.js` 动态注入，纯 HTTP 拿不到正文；`chapterUrl` 追加 `,{"webView":true}`，正文取 `@css:#chapter-content@html`

**QQ浏览器-完整分类-v7**

- 原因：`searchUrl` 依赖 `bodyJs`，引擎未执行导致 `JSON 列表规则未命中（0 项，响应 24942 字符）`
- 修复：直接解析 `$.data.state[*].items[*]`；`name=$.title`、`author=$.author`、`coverUrl=$.cover_url`、`intro=$.abstract`、`kind=$.tag_views`
- `bookUrl`：`https://novel.html5.qq.com/qbread/api/novel/bookInfo?resourceId={{$.docId##^.*_##}}`（docId 形如 `xxx_12345`，取尾段）
- 发现页保持不变

### 3.2 标注为上游问题（规则本身不改）

| 源 | 证据 |
|---|---|
| 塔读小说app v0.12 | 搜索接口返回 `code:303`（服务端风控），Python 复现同样失败 |
| 天域小说 / 爱奇电子书 | HTTP 404 |
| 速读谷 ×3 | HTTP 500（对方后端宕机） |
| 集书阁 | 连接超时 |
| 御书屋 | TLS 握手失败 |
| 台湾小说 | Cloudflare 403 |
| 茶马小说 | 搜索页 Cloudflare 403（首页 200） |
| 宝华书院 | 搜索为 JS 挑战页（动态 c2 校验） |
| bqg128 | 搜索走 `/user/search.html`，非浏览器会话固定返回 `"1"` |
| 得奇（重复条目） | 已 `enabled=false`，规则合并到主条目 |

### 3.3 去重（2026-10-29）

同域空壳已禁用，保留有规则/可用的同名条目：

| 被禁用 | 保留 |
|---|---|
| 🎧书音FM | 书音FM |
| 七猫 | ⭐七猫听书[官方]v0.2✨ |
| 八叉书库 | 八叉书库(二合一)☆夜明空☆ |
| 速读谷（第 2、3 条） | 速读谷（第 1 条，站点 500 观察用） |
| 得奇小说网（空壳重复） | 得奇小说网（已重建） |

当前源库：76 条，启用 **70** 条。

### 3.4 仍需整条重写（11 条，唯一站点）

`bqg128、🎃 言情小说网、🎨 漫蛙、365小说、肉书屋、阅友小说、台湾小说、🥕茶马小说、🌱米读小说、御书屋、宝华书院`

分类：
- **可重写但需 POST/JS**：言情（Ecms `/e/search/index.php`）、肉书屋（`POST /s.php`，响应慢且需 GBK）、365（搜索仅前端 JS）
- **API 签名**：米读（需签名/设备参数；七猫请直接用现成官方接口源）
- **非小说**：漫蛙（漫画）
- **反爬/下线**：台湾（Cloudflare 403）、茶马（搜索 CF 403）、宝华（JS 挑战）、bqg128（搜索 API 固定返回 "1"）、御书屋（TLS 失败）

## 4. 登录系统

已有能力（`14f09a6` + `b56b853`）：

1. 设置页 / 书源管理页 →「书源登录中心」：按已登录/未登录分组，支持搜索、左滑退出、form 登录与 WebView 登录。
2. `SourceLoginURLResolver`：`loginUrl` 为空或相对路径时回退到 `bookSourceUrl` 主页。
3. `SourceLoginView`：WebView 登录完成后把 `WKWebsiteDataStore` 全部 cookie 写入 `SourceCookieStore`。
4. `SourceCookieStore`：父域/子域匹配（本轮修复），引擎请求统一带 `Cookie` 头。
5. 阅读器与源管理页均有「登录书源」入口。

待真机验证：登录后搜索/目录/正文是否带 cookie（用 `GET /api/sources` 看 host cookie 数，或抓 `Cookie` 头）。

## 5. 下一轮验证顺序

```powershell
# 1) 等 1.0.96 构建
& 'D:\python\python.exe' 'E:\codex-temp\sourceread\scripts\check_ci.py' codex/swift-v2-lifetime-reader
# 2) 下载 IPA
& 'D:\python\python.exe' 'E:\codex-temp\sourceread\scripts\fetch_ipa.py' <ipa_run_id>
# 3) 手机导入源库（分批 ≤1.7MB）
& 'D:\python\python.exe' 'D:\Gemini反重力\SourceReadSwift2\tools\lan_import.py' 'D:\Gemini反重力\SourceReadSwift2\docs\sources\shareBookSource11-fixed-1.0.95.json'
# 4) 全量复测
& 'D:\python\python.exe' 'E:\codex-temp\sourceread\scripts\lan_source_check.py' --base http://192.168.31.205:8080 --keyword 斗破苍穹 --concurrency 3 --timeout 150
```

单源验证（得奇/QQ）：

```powershell
curl "http://192.168.31.205:8080/api/source/debug" -H "Content-Type: application/json" -d "{\"source\":<源JSON>,\"keyword\":\"斗破苍穹\",\"step\":\"all\"}"
```

## 6. 已知限制

- 得奇正文依赖 WebView，首次打开慢 1–3 秒；若 WebView 被系统回收会重试一次。
- QQ浏览器只保留「QQ浏览器」搜索结果，不再合并 QQ阅读（bodyJs 合并逻辑未在引擎执行）。
- 空壳源中有 4 条属于反爬/JS 挑战，短期不建议投入；需要浏览器内核才能过。
- iOS 16 兼容与阅读模式问题不在本轮范围，沿用 1.0.95 的修复。
