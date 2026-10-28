# CODEX 交接 — v1.0.76 (Build 77)

> **分支**：`codex/reader-feedback-fixes`
> **代码提交**：`8e15eb1`（fixture charset）→ `f8f9e77`（索引语法）→ `c6e49df`（`@html`/`@all`）→ `6eec467`（负区间断言修正）→ `5ceda53`（多段旧式索引 + JSON 前导点）→ `3086014`（okhttp3）
> **发布提交**：`5df9d3a`（版本 1.0.76 / Build 77）
> **日期**：2026-10-28
> **上一版**：v1.0.75 (Build 76) / `af9a086`
> **本轮输入**：997 条 Legado 书源统计 + 17 条真实搜索响应 + 6 张真实目录页
> **验证**：iOS run `40613012622` / job `122569378462` = **1186 tests / 0 failures**（`3086014`）

---

## 一、结论先行

1. **17 条真实源搜索全部有行**。上一轮 16 条搜索通过、QQ阅读 0 行、精华书阁目录 0 节点；本轮 17/17 达标，QQ阅读 10 行，精华书阁目录 20 章（与 Legado 模拟值一致）。
2. **Legado 索引语法补齐**。`AnalyzeByJSoup.ElementsSingle.getElementsSingle` 的区间、步长、负索引、排除、反向全部落地；`[1:-1]` 按 Legado 语义包含末元素，不是 Python 切片。
3. **`@html` / `@all` 对齐 `outerHtml`**。`html` 先删 `script`/`style` 再取整段 outerHtml；`all` 直接拼接 outerHtml。此前返回的是 `innerHtml`（或文本），凡是用 `@html` 取富文本/去广告的源都会偏。
4. **JSON 列表前导点降级**。`.bookList[*]` 直接命中失败时按 `$..bookList[*]` 做后代扫描，覆盖 `{"data":{"bookList":[…]}}` 这种包一层的返回。
5. **`Packages.okhttp3` 桥接**。`Request.Builder` / `OkHttpClient.newCall().execute()` / `RequestBody` / `MediaType` 映射到既有注入网络层，醉读小说、顶点小说这类把 HTTP 写在 `<js>` 里的源不再首行进 `catch`。
6. **CI 1186 tests / 0 failures**；版本 1.0.76 / Build 77。

---

## 二、逐项改动

### 2.1 五条真实 fixture 补 `charset`（`8e15eb1`）

`SourceReadSwiftTests/Fixtures/real-sources/index.json` 的 index 12–16（QQ阅读、新笔趣阁、笔趣阁[biqusa]、影书小说[修复]、爱看书网（优））缺少 `charset`，解码按默认编码走，中文响应被截断。补齐 `"charset": "utf-8"` 后 17 条 fixture 全部可解码。

### 2.2 Legado 索引语法（`f8f9e77` + `5ceda53` + `6eec467`）

文件：`SourceReadSwift/Core/Rules/LegadoDefaultRuleTranslator.swift`（LF）

- 新增 `LegadoIndexItem { single(Int) | range(start: Int?, end: Int?, step: Int) }` 与 `indexItems` / `excludeIndexItems`；`indices` / `excludeIndices` / `index` / `excludeIndex` 保留为兼容视图。
- `parseIndexItems(_:allowRanges:)`：
  - `[...]` 内（`allowRanges: true`）：`1:3` 是闭区间；`8:`、`1:-1`、`3:-2:-10`、`[3,4]`、`[!1,2,-2]` 全部支持。
  - 旧式 `.1:3` / `@1:3` / `!0:1:2:3:4`（`allowRanges: false`）：冒号是**多个独立索引**，段数不限。
- `executeSteps` 走 `resolveIndexSet`，逐条镜像 Legado：
  - 负索引 `+ count`；两端同侧越界丢弃；单端越界裁剪到边界；
  - `start == end` 或 `step >= count` 只取 `start`；
  - `end < start` 反向展开（`[-1:0]` 整表反向）；
  - 按出现顺序去重（等价 Legado 的 `LinkedHashSet`）。
- `6eec467` 修正测试断言：`[1:-1]` 在 Legado 中是 `1...(count-1)` **含末元素**。

### 2.3 `@html` / `@all` 语义（`c6e49df`）

文件：`SourceReadSwift/Core/Rules/HtmlRuleExtractor.swift`（LF）

- 新增 `joinedAllValue`（outerHtml 拼接）与 `stripScriptAndStyle`。
- `html`：删除 `script` / `style` 后返回 outerHtml（对应 `AnalyzeByJSoup.kt` L229-234）。
- `all`：返回 outerHtml 拼接（对应 L237）。
- XPath / Legado / fallback 三条路径统一调用同一实现。
- 连带：`BookDetailParser` 新增 `introPlainText`，简介里的 `<br>` / `</p>` / `</div>` 转换行、其余标签剥离，避免详情卡片直接显示 `<div class="intro">`。

### 2.4 JSON 列表前导点降级（`5ceda53`）

文件：`SourceReadSwift/Core/Rules/JSONRuleExtractor.swift`（LF）

`list(from:rule:variables:)` 在直接路径 0 行且路径以 `.` 开头（排除 `..`、`||`、`&&`）时，重试 `"$.." + path.dropFirst()`。QQ阅读 `bookList: ".bookList[*]"` 的数组位于 `data.bookList`，由此从 0 行恢复到 10 行。直接命中优先，不影响既有源。

### 2.5 `Packages.okhttp3` JS 桥（`3086014`）

文件：`SourceReadSwift/Core/JavaScript/JSCoreRuntime.swift`（LF，插在 `if (typeof URL === 'undefined')` 之前）

- `Packages.okhttp3.Request`：`url()` / `toString`。
- `Packages.okhttp3.Request.Builder`：`url` / `addHeader` / `header` / `removeHeader` / `get` / `head` / `post` / `put` / `delete` / `method` / `build`。
- `Packages.okhttp3.OkHttpClient().newCall(request).execute()`：复用 `__makeConnect`，套 header / method / body；`cancel` / `isCanceled` 兜底。
- `RequestBody.create`、`MediaType.parse`。

### 2.6 版本（`5df9d3a`）

`AppVersion.swift`、`project.yml`、`Info.plist`、`SearchURLResolverTests` 同步到 **1.0.76 / Build 77**；四个文件保持 CRLF。

---

## 三、真实源回归矩阵

### 3.1 搜索（17 条，`SEARCH` 行来自 job `122569378462`）

| 源 | 解析行数 | 源 | 解析行数 |
|---|---|---|---|
| ⚡📂错层小说 | 1 | 松鹤阅读 | 18 |
| 错层小说网 | 1 | 精华书阁手机版 | 20 |
| 笔趣阁[biquge7] | 18 | 看书网 | 17 |
| 开心文学网 | 15 | 阅友小说（优） | 5 |
| 中文万维（优） | 20 | 穿越小说（优） | 100 |
| 茶马小说（优++） | 1 | 起步新榜（优） | 20 |
| QQ阅读 | 10 | 新笔趣阁 | 18 |
| 笔趣阁[biqusa] | 50 | 影书小说[修复] | 50 |
| 爱看书网（优） | 20 | | |

### 3.2 目录（6 条，`TOC` 行来自同一 job）

| 源 | 解析 | Legado 模拟 |
|---|---|---|
| ⚡📂错层小说 | 4 | 4 |
| 错层小说网 | 4 | 4 |
| 精华书阁手机版 | 20 | 20 |
| 笔趣阁[biquge7] | 1838 | 1838 |
| 看书网 | 100 | 100 |
| 开心文学网 | 30 | 30 |

---

## 四、剩余能力缺口（不阻塞发布）

| 优先级 | 项 | 规模 | 结论 |
|---|---|---|---|
| P3 | `concurrentRate` | 997 条里 5 条 | 未实现；需要在请求层按源 key 做令牌桶 |
| P3 | `options.js` | 1 条（`java.toast`） | 收益≈0，不做 |
| P3 | `@result` | 0 条 | 不做 |
| 观察 | `||` 回退顺序 | 搜索 43 / 目录 16 | 现有“首个非空”未出现反例，等真实源反例再动 |

---

## 五、验证与产物

| 项 | 值 |
|---|---|
| iOS CI | run `40613012622` / job `122569378462`，**1186 tests / 0 failures** |
| 发布构建 | run `40614309255`（Unsigned IPA） |
| IPA | `C:\Users\Edc21\Desktop\SourceReadSwift-1.0.76-unsigned.ipa`（12,250,999 字节） |
| SHA256 | `83C858C9B363436BE1166ECED6E16E69CC3B612E4389D429AAC2353F6A2CF8B2` |
| 版本 | `1.0.76 / 77`，MinimumOSVersion 16.0 |
| 研究补篇 | `docs/SOURCE_COMPAT_1_0_76.md` |
| 全量记录 | `PROJECT_FULL.md` §二十七 |

本轮只动解析层与 JS 桥，未改阅读器 UI；iOS 16 结论沿用 `docs/IOS16-COMPAT-AUDIT-1.0.65.md`。

---

## 六、下一步

1. 真机回归：17 条真实源在 iOS 16 / 17+ 上各跑一次搜索 + 目录 + 正文。
2. 997 条源在线抽样：把“连接失败 / 4xx / 空结果 / 解析 0 行”分开统计，只有最后一类才归解析器。
3. `||` 回退顺序：收集 43 条搜索源的真实响应，出现“前段命中但内容不对”的反例再改。
4. `concurrentRate`：有 5 条源依赖，若真机出现 403/限流再实现。
