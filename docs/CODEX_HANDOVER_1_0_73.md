# CODEX 交接 — v1.0.73（Build 74）

> **分支**：`codex/reader-feedback-fixes`
> **代码提交**：`a4c066b`
> **日期**：2026-10-28
> **上一版**：v1.0.72 (Build 73) / `39310c2`
> **验证**：iOS run `40598707154` / job `122521108228` = **1153 tests / 0 failures**；IPA run `40598707151`
> **产物**：`C:\Users\Edc21\Desktop\SourceReadSwift-1.0.73-unsigned.ipa`（12,206,072 字节，SHA256 `AAD4E89D7515E477070B45F51F3645FBE516C022D63C5B2CE275AC652AA86951`，`1.0.73 / 74`，MinimumOSVersion 16.0）

---

## 一、这一轮补的是哪些 Legado 语义

前 3 个版本（1.0.69/1.0.70/1.0.71/1.0.72）已经补掉了：`{{key}}` 的 Java `URLEncoder` 语义、WebView 三件套（`sourceRegex` / `webJs` / `overrideUrlRegex`）、单请求 20 秒预算、空解析三级文案、POST 表单体关键字编码、`@js:` 整条 URL 的 `result` 绑定。

本轮对照 `AnalyzeUrl.kt` 逐条核剩下没落地的部分，补了 3 组：

| Legado 位置 | 语义 | 本轮状态 |
|---|---|---|
| `AnalyzeUrl.kt` L226-236 | `charset == "escape"` → `EncoderUtils.escape(value)` | 已实现 |
| `AnalyzeUrl.kt` L187-189 | `UrlOption.retry` / `webView` / `webJs` | 已实现 |
| `AnalyzeUrl.kt` L185 / L190-194 | `UrlOption.type` / `UrlOption.js` | 已解析，`js` 尚未消费（见 §四） |

---

## 二、改动明细

### 2.1 `charset: "escape"`

Legado `EncoderUtils.escape`（`app/src/main/java/io/legado/app/utils/EncoderUtils.kt` L12-29）不是浏览器 `escape()`：

- 只保留 ASCII 字母和数字，`- _ . * @ / +` **全部转义**；
- `charCode < 16` → `%0X`，`< 256` → `%XX`，其余 → `%uXXXX`；
- 十六进制小写（`-` → `%2d`，不是 `%2D`）。

新增 `LegadoRuleResolver.escapeEncode` 逐行复刻，并由 `encodeKeyword` 按 charset 分派；`LegadoRuleResolver.interpolate` 统一走 `encodeKeyword`。

更关键的是**取 charset 的位置**：之前只有 `SearchURLResolver.isGBKEncoding` 这个启发式（扫文本里有没有 `gbk`），`charset: "escape"` 会被判成「非 GBK」→ 传 `nil` → 退回 UTF-8 百分号编码。新增 `SearchURLResolver.charset(searchUrl:source:)` 先读 URL 选项 JSON 里的 `charset` / `encoding` / `encode`，读不到才回落到 GBK 启发式。`SourceRequestBuilder.buildSearchRequest` 与 `SearchURLResolver.resolve` 的 3+3 处调用点全部改用它。

### 2.2 URL 选项 `webView` / `webJs` / `retry`

`SourceURLDirectiveParser` 之前只认 `headers` / `method` / `body` / `charset` / `timeout`。现在补 4 个字段：

| 选项 | 解析规则 | 依据 |
|---|---|---|
| `webView` | **键存在即为 true**，`{"webView": false}` 也算 | `option.webView?.toString()?.isNotBlank() == true`（L188） |
| `webJs` | 字符串，覆盖本次请求的 `ruleContent.webJs` | L189 |
| `retry` | 正整数，最多 5 次 | L187 |
| `type` | 值为合法 HTTP 动词时仍当 method，否则记为 `responseType` | L185 |

链路：`SourceURLDirective` → `SourceRequest`（新增 `webView` / `webJs` / `retry`，带默认值，`SourceImportDownloader` 等旧调用点不改）→ `SourceRequestBuilder.buildRequest` 透传 → `SourceEngine.loadWithOptionalWebViewFallback` 消费：

- `webView == true`（且 `allowWebViewFallback`、非 LiveContainer）→ **不发普通 HTTP 请求**，直接进 `WebViewFallback`；
- `webJs` 优先于 `ruleContent.webJs`；
- `retry` 走新增的 `loadWithRetry`，成功即短路。

### 2.3 测试

`BookSourceTests` 新增 7 条：

- `testLegadoEscapeEncoderMatchesAndroidEncoderUtils`
- `testInterpolateHonoursLegadoEscapeCharset`
- `testURLDirectiveParsesLegadoWebViewOption`
- `testURLDirectiveTreatsPresentWebViewKeyAsEnabled`
- `testURLDirectiveKeepsHTTPVerbTypeAsMethod`
- `testSearchRequestCarriesWebViewAndRetryOptions`
- `testSearchRequestPicksUpEscapeCharsetFromURLJSON`

1153 = 上一版 1143 + v1.0.72 的 3 条 + 本轮 7 条。

---

## 三、交叉验证：两款已解包 iOS 阅读器

桌面上的 `开元阅读-3.0.1-逆向解包` 与 `栖阅2026.6.08-逆向解包` 提供了两条独立证据。

### 3.1 `URLEncoder` 语义一致

栖阅 `01_交付包/js/packages_stub.js` L963-983 的 `Packages.java.net.URLEncoder.encode`：

- 空格 → `+`；
- 保留 `A-Z a-z 0-9 * - . _`；
- 其余 `%XX` 大写。

与本项目 `LegadoRuleResolver.percentEncode` 完全一致 —— v1.0.72 的实现方向得到第三方产品验证。

### 3.2 书源字段真实分布

栖阅 `01_交付包/reports/legado_source_keys.txt` 是它二进制里书源字段的出现频次。带 `login*` 的项：

| 字段 | 出现次数 | 本项目当前 |
|---|---:|---|
| `loginUrl` | 9 | 已支持（`SourceLoginURLResolver`） |
| `loginCheckJs` | 7 | 已支持 |
| `loginUi` | 14 | **缺失** |

`loginUi` 是 Legado 的配置驱动登录表单（`RowUi(name, type, action)`，`type ∈ text/password/button`），`SourceLoginDialog` 收集输入后写入 `loginInfo`，再由 `loginJs`（即 `loginUrl` 去掉 `@js:` / `<js>` 前缀）执行真正的登录请求。本项目 `SourceLoginView` 只有 WebView 一种模式，所以 `loginUi` 源只能落到「打开 loginUrl 网页」——而这类源的 `loginUrl` 往往是一个 POST 接口，浏览器打开就是空页或 404，这正是「登录地址无效 / 根本没有登录选项」的来源。

JS 侧其实已经就绪：`JSCoreRuntime` 已提供 `source.getLoginInfoMap` / `putLoginInfo` / `setLoginInfo` / `removeLoginInfo`，`RuleExecutionContext` 有 `keys(withPrefix:)` / `removePrefix(_:)`。缺的只有模型字段、表单 UI、以及「存 loginInfo → 执行 loginJs」这一段 Swift 编排。

### 3.3 架构可行性

栖阅是纯原生 SwiftUI + JavaScriptCore + WKWebView，靠 `packages_stub.js`（56 KB）仿真 `javax.crypto` / `jsonpath` / `GZIP`，靠 `jsoup_bridge.js`（26 KB）仿真 `org.jsoup` + `JXDocument`。说明本项目「TextKit 渲染 + JSCore 跑规则 + WebView 兜底」的路线在 iOS 上是被商业产品验证过的，不需要换引擎。

---

## 四、仍未落地（下一轮）

| 优先级 | 项 | 现状 | 下一步 |
|---|---|---|---|
| P1 | `loginUi` 表单登录 | 0 处引用 | 模型字段 → `[RowUi]` 解析 → SwiftUI 表单 → 存 `source.login.*` → 执行 `loginJs` → `loginCheckJs` 校验 |
| P2 | `concurrentRate` 并发限速 | 0 处引用 | 解析 `"4/1000"` → actor 级令牌桶，按源 key 限速 |
| P2 | `UrlOption.js` | 已解析、未消费 | 对最终 URL 执行 JS（变量 `result` = url），结果替换 URL |
| P3 | `@result` 文本占位 | 未做 | `AnalyzeUrl.analyzeJs` L109/L118；真实书源极少使用 |
| P3 | `ruleReview` / `ttsSource` | 0 处引用 | 独立功能域，与本轮解析链路无关 |

`type`（`responseType`）已解析但暂未改变解析器选择：现有 `SearchResultParser` / `ChapterListParser` 的 JSON↔HTML 互查已覆盖同类场景，直接按 `type` 硬切反而会丢掉兜底。

---

## 五、验证方法

```bash
# 版本
defaults read Payload/SourceReadSwift.app/Info.plist CFBundleShortVersionString   # 1.0.73
defaults read Payload/SourceReadSwift.app/Info.plist CFBundleVersion              # 74

# 书源：构造一个带 escape 的源，观察请求 URL
# searchUrl = https://example.com/search?q={{keyword}}, {"charset":"escape"}
# 关键词「剑来」→ q=%u5251%u6765（经 URL 规范化后为 %25u5251%25u6765，与 OkHttp canonicalize 行为一致）

# 书源：构造一个 webView 源，观察诊断
# searchUrl = https://example.com/api, {"webView":true,"retry":2}
# 诊断里应出现 stage=search.load.webview，且不出现普通 HTTP 请求记录
```

CI 入口：`gh run view 40598707154 --log`（测试） / `40598707151`（IPA）。

---

## 六、回滚

单文件回滚即可，无数据结构迁移：

- `SourceURLDirective.swift` / `SourceRequest.swift` / `SourceRequestBuilder.swift` / `SourceEngine.swift` → 恢复 `39310c2`
- `LegadoRuleResolver.swift` / `SearchURLResolver.swift` → 恢复 `39310c2`
- 版本号四处（`project.yml` / `Info.plist` / `AppVersion.swift` / `SearchURLResolverTests.swift`）→ 恢复 `1.0.72 / 73`
