# CODEX 交接 — v1.0.77 (Build 78)

> **分支**：`codex/reader-feedback-fixes`
> **代码提交**：`1a965b0`（URL 选项宽松解析）→ `24ba8b1`（concurrentRate + 版本号）→ `38ba450`（版本断言）
> **日期**：2026-10-28
> **上一版**：v1.0.76 (Build 77) / `5df9d3a`
> **验证**：iOS run `40619907231`、IPA run `40619907109`，均 success
> **产物**：`C:\Users\Edc21\Desktop\SourceReadSwift-1.0.77-unsigned.ipa`

---

## 一、结论先行

1. **URL 选项解析放宽**。Legado 书源里大量 `@Header:{'a':'b'}`、引号不配对、`{...};` 后跟 `@js:` 尾巴、`java.connect(su,{})` 这类非标准写法，现在都能解析；`js:` 开头的纯脚本规则不再被 URL 切分逻辑腰斩。
2. **`concurrentRate` 落地**。997 条源里有 5 条配置了并发率（`500`、`700`、`200`、`20/60000`），此前完全忽略；现在 HTTP 请求、JS 内 `java.ajax` 共用同一个按源隔离的限流窗口，语义对齐 `ConcurrentRateLimiter.kt`。
3. **阅读器排版没有回退**。1.0.65/1.0.68 的标题字号、段距、去重、TextKit 分页仍是当前实现；本轮只补书源链路，不重复改这些。
4. **CI 全绿，IPA 已出**：1.0.77 (Build 78)，最低 iOS 16.0。

---

## 二、逐项改动

### 2.1 URL 选项：单引号、不配对引号、尾随脚本（`1a965b0`）

文件：`SourceReadSwift/Core/Network/SourceURLDirective.swift`

- 规则以 `@js:` / `<js>` / `js:` 开头时不再切分 URL，避免把 `java.connect(su,{})` 里的 `{` 当成选项对象。
- 新增 `firstBalancedObject(in:)`：引号感知地截取第一个配对的 `{...}`，丢掉 `};`、反引号与后面的 `@js:` 尾巴。
- `sanitizeRelaxedJSON` 改为逐字符扫描：单引号字符串转双引号、内嵌双引号转义、未闭合单引号在换行处收尾、裸键补引号、去尾逗号。
- `parseOptionsObject` 三级回退：标准 JSON → 宽松 JSON → JS eval。
- `charset` 值去掉首尾引号（修 `'charset': 'UTF-8"'`）。

回归：`SourceReadSwiftTests/SourceURLDirectiveTests.swift` 新增 6 条，覆盖爱下小说、零点看书、大米小说、酷我音乐、`java.connect`、第二对象尾巴。

### 2.2 concurrentRate：请求节流（`24ba8b1`）

文件：
- `SourceReadSwift/Core/Network/SourceRateLimiter.swift`（新增）
- `SourceReadSwift/Core/Models/BookSource.swift`（`concurrentRate` 计算属性）
- `SourceReadSwift/Core/Network/SourceRequest.swift`（`concurrentRate` / `rateLimitKey`）
- `SourceReadSwift/Core/Network/SourceRequestBuilder.swift`（从源带入请求）
- `SourceReadSwift/Core/Engine/SourceEngine.swift`（`loadWithRetry` 取号）
- `SourceReadSwift/Core/Network/SynchronousSourceNetworkBridge.swift`（JS 网络调用共用）

语义（对齐 Android `ConcurrentRateLimiter.kt`）：

| 配置 | 行为 |
|---|---|
| 缺省 / `""` / `0` | 不限速 |
| `500` | 同一时刻一个请求，两次请求开始时间至少间隔 500 ms |
| `20/60000` | 60 s 窗口内最多 20 次，窗口从第一次请求开始计时 |

997 条源实测配置：得奇小说 `500`、立方体儿 `700`、言情小说 `200`、鱼鱼小说 `20/60000`、梧桐中文 `500`。

回归：`SourceReadSwiftTests/SourceRateLimiterTests.swift` 6 条（解析、拒绝非法值、请求透传、间隔模式等待、窗口模式阻塞、共享实例不影响其它源）。

### 2.3 版本断言（`38ba450`）

`SourceReadSwiftTests/SearchURLResolverTests.swift` 的 `testAppVersionSemantics` 硬编码 1.0.76 / 77，bump 后失败；改为 1.0.77 / 78。

---

## 三、证据

| 项 | 值 |
|---|---|
| iOS CI | run `40619907231`，success（build + test） |
| IPA CI | run `40619907109`，success |
| 版本 | 1.0.77 / Build 78 |
| 最低系统 | iOS 16.0 |
| IPA | `C:\Users\Edc21\Desktop\SourceReadSwift-1.0.77-unsigned.ipa` |
| 大小 | 12,266,727 字节 |
| SHA256 | `812DB2CF43CCA94D99239BD6526F3971855E568CEB85DE008A0E5684D6143FFF` |

---

## 四、本轮没有改的东西（避免重复劳动）

阅读器三项能力在 1.0.65–1.0.68 已落地，本轮未回退、也未重写：

- 三种翻页模式共用同一 TextKit 页：`ReaderView.pagedReaderContent` 的 cover / pageCurl / pageTurn 都走 `readerPage(for:)` → `ReaderPageTextView`（`UITextView(usingTextLayoutManager: false)`）。
- 标题字号：`ReaderTypographyDefaults.titleFontSize` = `max(1.3 × 正文, 正文 + 6)`，标题 bold；页眉/正文大标题/隐藏三种模式由 `ReaderPageChromeLayout` 控制。
- 段距 16pt > 行距 8pt；数字章节标题去重；中文标点 `pushOut` 悬挂。

对应提交：`c711e9e`（TextKit 分页）、`ffb9da4`（iOS 16 布局加固）、`01ec90b`（页标识锚定，修跳回上一页）、`68e4253`（1.0.65 标题/分页）、`1fe7d6d`（1.0.67 标点）、`eae2e94`（1.0.68 段距/去重）。

---

## 五、下一轮待办

1. 158 条真实搜索响应：jsoup 行数 vs Swift 行数差异表（`rows_counts2.tsv` 已有 114 有行 / 44 零行基线）。
2. `HTML规则||JSONPath规则` 混写在 HTML 通道中仍跳过 JSON 分支（`HtmlRuleExtractor.swift` L148-170 / L530-545）。
3. `webView: true` 在搜索 / 目录 / 正文三阶段的覆盖确认（18 条源）。
4. iOS 16 真机矩阵：iPhone 14 Pro Max / 16.3.1、iPhone 13 / 17.x，重点看阅读页顶部安全区与封面回退。
