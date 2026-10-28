# 私人书源验证报告（1.0.89）

日期：2026-10-28
对象：用户提供的两份书源文件
- 文件 1：`D:/QQ游戏/shareBookSource (2).json`（番茄书源，源名 `番茄小说TS`）
- 文件 2：`D:/QQ游戏/bookSource_202610111309.json`（103 条私人书源合集）

## 1. 文件 1：番茄小说TS —— 可用

| 项 | 实测 |
|---|---|
| `bookSourceUrl` | `https://fq.tangsongxs.com` |
| `searchUrl` | `@js:`，内部走 `/search?query=..&offset=..&tab_type=..` |
| 小说 `tab_type=3` | HTTP 200，7,089 B，首条《神通者》天蚕土豆 |
| 听书 `tab_type=2` | HTTP 200，3,497 B |
| 短剧 `tab_type=11` | HTTP 200，5,664 B |
| 漫画 `tab_type=5` | HTTP 200，117 B（`items:null`，站点侧为空） |
| 详情 `/detail?book_id=7665193065501445145` | HTTP 200，1,413 B |
| 目录 `/catalog?book_id=...` | HTTP 200，51,734 B，`data.item_data_list` 完整 |

端到端回归（1.0.89 新增）：

- fixture：`SourceReadSwiftTests/Fixtures/private-bank/tomato-source.json`（源原样）
- 真实响应：`SourceReadSwiftTests/Fixtures/private-bank/tomato-search.json`（`tab_type=3`，HTTP 200）
- 测试：`PrivateBankSourceTests`
  1. 源可解码（`@js:` searchUrl、36,889 B jsLib、exploreUrl 非空）
  2. `SearchURLResolver` 用 `key=系统&page=1` 解析出 `https://fq.tangsongxs.com/search?...&tab_type=3&offset=0`
  3. `SearchResultParser` 从真实响应解析出 ≥1 本，`bookUrl` 含 `/detail?book_id=`

结论：源可用；小说/听书/短剧三条 API 均活，漫画当前站点返回空。

## 2. 文件 2：103 条合集 —— 不是「只有 3 个能用」

### 2.1 静态分类

| 类别 | 数量 | 说明 |
|---|---|---|
| 总数 | 103 | |
| 无 `searchUrl` | 26 | 纯发现/详情源，搜索本来就不适用，不是坏源 |
| 有 `searchUrl` | 77 | 其中 `@js:` / `<js>` 占多数 |
| 带 `jsLib` | 47 | 最大 587 KB（七猫四合一本地版） |
| 带 `loginUrl` | 45 | 私人接口多数需要登录态 |
| 带 `loginUi` | 40 | |
| 带自定义 `header` | 36 | |

### 2.2 JS 求值（Node 最小 Legado 桥）

对 77 条可搜索源执行 `searchUrl` 的 JS / 模板求值（`key=斗破苍穹, page=1`）：

| 结果 | 数量 |
|---|---|
| 得到 URL（含 2 条带备注） | 63 |
| 无 searchUrl | 26 |
| JS 求值失败 | 16（另 2 条算出 URL 但带备注） |

16 条失败归因：

- 6 条：`source.get is not a function`（知秋/神魔系 jsLib 把 `source` 当 Map 用）→ **1.0.89 已修**：JSCoreRuntime 两处注入点补 `source.get / put / remove` 别名
- 6 条：`Packages` / `java.createSymmetricCrypto` / `java.get(...).body` / `cookie.getCookie` → Node 桩缺口，App 内已有这些桥，不需要改
- 2 条：源自身写坏（`<<js>` 多一个 `<`、依赖作者私有函数 `lycnm`）
- 2 条：其它模板/库错误（待真机日志确认）

### 2.3 URL 层 HTTP 实测（63 条得到 URL / 58 次实际请求）

| 结果 | 数量 |
|---|---|
| 实际发出 HTTP 请求 | 58 |
| HTTP 200 且 ≥200 B | 40 |
| HTTP 200 但 <200 B（空壳） | 6 |
| HTTP 5xx | 8（速读谷 ×3 为站点 500） |
| HTTP 4xx | 4 |
| 网络错误（SSL / 连接 / URL 非法） | 4 |
| 模板未解析 | 1 |

### 2.4 内容层判定（40 条 200 响应）

| 判定 | 数量 | 含义 |
|---|---|---|
| `keyword-hit` | 31 | 响应正文出现「斗破苍穹」，真实返回了搜索结果 |
| `list-shape` | 6 | 有列表结构（`items/data/books/li/dl`），关键词可能被转义或站点忽略 |
| `200-no-signal` | 3 | 200 但无关键词、无列表 |
| `empty-body` | 6 | 200 但 <200 B |

关键词命中示例：番茄小说TS、红果小说[官方]、番茄听书[官方]、七猫小说、七猫小说[官方本地接口]API、书旗、QQ浏览器-完整分类、Icu、听中国听书、17K小说-API、圣灵聚合、木里番茄、日落小说等。

### 2.5 结论

- 「100 个只能用 3 个」与实测不符：**26 条源有强证据返回搜索结果，5 条弱命中，合计 31 条**；另有 6 条返回列表结构。
- 26 条无 `searchUrl` 的源是发现/详情源，应改用「发现」入口验证，不能按搜索可用性判死。
- 站点侧问题占失败大头：速读谷 500 ×3、502 ×4、404 ×3、403 ×1、SSL/连接/URL 非法 ×4；私人源还普遍需要登录态（45 条有 `loginUrl`），未登录时返回空/错误属预期。
- 1.0.89 修复的 `source.get/put/remove` 直接解锁 6 条知秋/神魔系源（神魔小说、番茄四合一知秋、UAA四合一、刺猬猫阅读等），真机需再验。

## 3. 复现命令

- JS 求值：`E:/codex-temp/sourceread/scripts/eval_search_urls.js`
  `node eval_search_urls.js "D:/QQ游戏/bookSource_202610111309.json" out.json "斗破苍穹" 1`
- URL 层实测：`E:/codex-temp/sourceread/scripts/live_103c.py`
- 内容层判定：`E:/codex-temp/sourceread/scripts/live_103d.py`
- 产物：`sources103-urls.json`、`sources103-live3.tsv`、`sources103-content.tsv`

## 4. 边界

以上为 URL + HTTP + 正文关键词层证据，不等于「每条源的 ruleSearch 都能在 App 里解析出书目」。完整 ruleSearch/目录/正文解析仍需 App 运行时逐条跑；番茄源已用 fixture 做到端到端（解码 → URL → 解析）。
