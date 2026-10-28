# CODEX 交接 — v1.0.75 (Build 76)

> **分支**：`codex/reader-feedback-fixes`
> **提交**：`10545a5`（1.0.75 主体）+ `371248b`（开心文学网 fixture 行数）+ `af9a086`（`@attr` 规则修复与 TOC 回归集）
> **日期**：2026-10-28
> **上一版**：v1.0.74 (Build 75) / `1b1bf83`
> **本轮输入**：997 条 Legado 书源全量统计 + 12 条真实站点响应 + 6 张真实目录页

---

## 一、结论先行

1. **搜索为空的最大单点已修**：`checkKeyWord` 被错误地当成过滤条件。997 条源里 174 条配置了它，Legado 只在调试界面当提示，从不参与 `BookList` 过滤。1.0.75 删除该过滤，配置了 `checkKeyWord` 的源不再整行丢失。
2. **`@onclick@js:` 这类链式属性规则已修**：旧实现把 `@onclick` 的 `@` 丢掉，当成标签选择器 `onclick`，bookUrl 永远为空；或者把元素桥接对象绑给 `result`，`result.match(...)` 拿不到字符串。现在 `@attr` 规则直接作用于当前节点，链式 `@js:` 绑定属性文本。
3. **真实源第一次进入 CI**：12 组搜索响应（8 HTML + 4 JSON）+ 6 张目录页（含 1838 章的笔趣阁），解析行数与 Legado 语义逐条对齐。
4. **`options.js` 不再是待办**：全库唯一一条（大美书网）是 `java.toast('正在搜索中，请稍等！')`，Legado 里返回 undefined 时 URL 不变，纯提示，收益≈0。
5. CI：**1167 tests / 0 failures**；IPA 已产出。

---

## 二、v1.0.75 改动

### 2.1 `checkKeyWord` 语义修正（`10545a5`）

文件：`SourceReadSwift/Core/Rules/SearchResultParser.swift`（CRLF）

- 删除 L173 `guard passesCheckKeyWord(...)`；
- 删除 L345 的整行 `filter`；
- 删除整个 `passesCheckKeyWord` 方法。

依据：Legado `BookList.kt` 的搜索链路从不读取 `checkKeyWord`；`BookSourceDebugActivity.kt` L85-89 只把它显示为“校验关键字”提示。此前我们的实现把它当硬过滤，导致 174 条源在关键词与 `checkKeyWord` 不一致时返回 0 行。

测试同步改名并改断言（`SourceMetadataChainTests.swift`，CRLF）：

- `testHTMLSearchKeepsEveryRowWhenCheckKeyWordIsConfigured`
- `testJSONSearchKeepsEveryRowWhenCheckKeyWordIsConfigured`

两条都期望 2 行，锁定“配置了也不过滤”。

### 2.2 真实源搜索回归集（`10545a5` + `371248b`）

`SourceReadSwiftTests/Fixtures/real-sources/`：

- 12 组 `.body` + `.json` + `index.json`；
- 8 条 HTML：错层小说、错层小说网、精华书阁、笔趣阁[biquge7]、看书网、开心文学网、阅友小说、茶马小说；
- 4 条 JSON API：松鹤阅读（带 JSONPath 过滤器）、中文万维、起步新榜、免费追书；
- 断言：`books.count >= expectedMinimum`，失败输出源名、实际行数、首本书名。

开心文学网 `bookList: ".grid@tr!0"` 的真实行数是 15（16 个 `<tr>` 去掉表头），`371248b` 把预期从 16 修正为 15。

### 2.3 `@attr` 规则与 `@onclick@js:` 链式绑定（`af9a086`）

失败样本（阅友小说（优））：

```json
"bookList": ".v-list-item",
"name": ".v-title@text",
"bookUrl": "@onclick@js:result.match(/\\('(.*?)', '', ''\\)/)[1]"
```

真实节点：`<div class="v-list-item flex" onclick="newWebView('/b/229093.html', '', '')">`。

根因两处：

1. `LegadoDefaultRuleTranslator.translateValueRule("@onclick")` 先按 `@` 切分，丢掉空段后得到 `["onclick"]`，`isAttributeToken("onclick")` 为 false、`isSelectorToken("onclick")` 为 true，于是被当成标签选择器 `onclick`，匹配不到任何节点。
2. `HtmlRuleExtractor.evaluateChainedJavaScript` 对前缀先 `select`，命中元素时把 `LegadoElementBridge` 绑给 `result`；Legado `getString` 链路里 `result` 应为属性字符串，`result.match(...)` 因此失败。

修复：

- `LegadoDefaultRuleTranslator` 新增前导 `@` 分支：`@onclick` / `@href` / `@text` / `@data-src` / `@attr:name` 直接返回 `steps=[selector:""]` + 对应属性，`##` 正则照常透传；`@css:` / `@json:` / `@js:` / `@xpath:` 不在本分支。
- `HtmlRuleExtractor.evaluateChainedJavaScript` 对属性前缀直接取字符串并绑定 `result`，不再先 `select`。

影响面：不止阅友一条源。`@href` / `@src` / `@text` 这种“在列表节点上直接取属性”的写法是全 Legado 生态的常规形态。

### 2.4 JS 运行时失败重置（同 `af9a086`）

`evaluateJSWithTrailingRegex` 拆为 wrapper + `evaluateJSWithTrailingRegexOnce`。一次 JSCore prelude 失败会污染整个阶段的缓存运行时，后续所有 `@js:` 规则都返回错误、整源塌成空。现在失败时 `executionContext.resetRuntime()` 后重试一次；链式递归继续走 `Once`，避免重复重置。

### 2.5 真实目录回归集（同 `af9a086`）

`RealSourceTOCRegressionTests` + 6 张 `.body` + `toc-index.json`：

| 源 | 实际解析 | emulated |
|---|---|---|
| ⚡📂错层小说 | 4 | 4 |
| 错层小说网 | 4 | 4 |
| 精华书阁手机版 | 20 | 20 |
| 笔趣阁[biquge7] | 1838 | 1838 |
| 看书网 | 100 | 100 |
| 开心文学网 | 30 | 30 |

断言取 `expectedMinimum = emulated / 2`，失败输出实际章数与首章名。测试执行 0.82 秒。

---

## 三、997 条源统计补充

### 3.1 `&&` 分布

| 字段 | 含 `&&` 的源数 |
|---|---|
| `ruleSearch` | 6 |
| `ruleToc` | 19 |
| `ruleContent` | 15 |
| `ruleExplore` | 7 |
| `ruleBookInfo.name` | 2 |

`RuleOperatorSplitter` 已按 Legado “首个顶层操作符”语义处理，暂不作为 bug。

### 3.2 `options.js` 降级

全库唯一一条（大美书网）：

```json
"js": "java.toast('正在搜索中，请稍等！');"
```

Legado `AnalyzeUrl.kt` L190-194 在 `evalJS` 返回 undefined 时保留原 URL，这条只弹提示。实现收益≈0，从 P1 降为 P3（记录在案，不做）。

### 3.3 其余长尾

| 项 | 源数 | 状态 |
|---|---|---|
| `concurrentRate` | 5 | 未实现（P3） |
| `@result` | 0 | 未实现（无样本） |
| `loginUi` | 13 | 1.0.74 已实现 |
| `loginUrl` | 107 | 1.0.74 已实现（表单 + 页面登录） |

---

## 四、验证

| 项 | 值 |
|---|---|
| iOS CI | run `40605778349` / job `122544790117`，**1167 tests / 0 failures** |
| 测试耗时 | 20.567 s（总 30.286 s） |
| Build | success（00:03:15） |
| IPA CI | run `40605778396` / job `122544792087`，success |
| IPA | `C:\Users\Edc21\Desktop\SourceReadSwift-1.0.75-unsigned.ipa` |
| 大小 | 12,246,665 字节 |
| SHA256 | `532EAFD3E8DCEED2CE0B63B629BA894066D3ACFA87BA094BC55B1F22F7425CF6` |
| 版本 | `1.0.75 / 76`，MinimumOSVersion 16.0 |
| Bundle ID | `com.edc21.SourceReadSwift` |

真实源断言输出（CI 日志）：

```text
RealSourceSearchRegressionTests: passed (1.325 s)
TOC ⚡📂错层小说: 4 chapters (emulated 4)
TOC 错层小说网: 4 chapters (emulated 4)
TOC 精华书阁手机版: 20 chapters (emulated 20)
TOC 笔趣阁[biquge7]: 1838 chapters (emulated 1838)
TOC 看书网: 100 chapters (emulated 100)
TOC 开心文学网: 30 chapters (emulated 30)
```

---

## 五、复现

```bash
# 搜索回归（macOS）
xcodebuild test -project SourceReadSwift.xcodeproj -scheme SourceReadSwift \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:SourceReadSwiftTests/RealSourceSearchRegressionTests \
  -only-testing:SourceReadSwiftTests/RealSourceTOCRegressionTests
```

真实源回归失败时的读法：

1. 先看源名与实际行数；
2. 行数为 0：检查 `bookList` 是否命中（选择器 / JSONPath / `||`）；
3. 行数在但字段空：检查 `name` / `bookUrl` 的前缀与属性绑定（本轮修的就是这一类）；
4. 目录页：先看 `chapterList` 命中数，再看 `chapterName` / `chapterUrl` 是否逐行非空。

---

## 六、剩余待办

| 优先级 | 项 | 说明 |
|---|---|---|
| P1 | `||` 回退顺序 | 43 条搜索 / 16 条目录；部分源第一段命中空列表时不会继续 |
| P2 | JSONPath 过滤器全覆盖 | 98 条 JSON 源；`[?(@.x == 'y')]` 已在 fixture 中 |
| P2 | `concurrentRate` | 5 条源；按源 key 的令牌桶 |
| P3 | `options.js` | 仅 1 条 toast，收益≈0 |
| P3 | `@result` | 997 条里 0 条使用 |

阅读侧不变：1.0.66 的页面身份锚定与 1.0.66-1.0.68 的排版修复都在当前分支；iOS 16 真机矩阵仍待验收。
