# 书源解析兼容性研究报告（v1.0.75 基线）

> 统计样本：`D:\QQ游戏\all_book_sources.json`（997 条 Legado 书源）
> 对照实现：Legado `AnalyzeUrl.kt` / `BookList.kt`（本地 `legado-src2`）、栖阅 2026.6.08 解包（`packages_stub.js` + `jsoup_bridge.js`）
> 采集时间：2026-10-28

## 一、结论先行

1. **"搜索为空 / 目录为空"的主因不是规则引擎，而是源站存活率。** 随机 60 条源按各自 `searchUrl` 真实请求，只有 18 条返回 200 且响应里含关键词；16 条返回 200 但页面无结果，12 条 4xx/5xx，8 条是纯 JS URL，6 条直接连接失败。剩下能用的源里，我们的解析器必须与 Legado 逐字段一致才有意义。
2. **URL 层语法我们已经对齐得比较完整**：`@js:` / `<js>`、`{{表达式}}`、`<1,2,3>` 分页模板、`,{...}` 选项（含单引号宽松解析）、POST body、GBK 关键字编码、`webView` / `webJs` / `retry` 都有实现（见第二节）。
3. **仍然缺的三项**：`UrlOption.js`（解析了但未消费）、`concurrentRate`（0 处引用）、`@result` 文本占位。前两项在 997 条里分别只命中 1 条和 5 条，属于长尾，不是"很多源搜不到"的原因。
4. **解析层的真实风险集中在 98 条 JSONPath 源和 43 条 `||` 组合源**。这两类一旦选择器翻译偏差，表现就是"搜索为空"，而日志里看不出区别。
5. **栖阅能在 iOS 跑 Legado 源的关键**不是规则引擎，而是 56 KB 的 `packages_stub.js`：在 JavaScriptCore 里铺了 `Packages.javax.crypto`、`java.security`、`org.jsoup`、`okhttp3`、`cn.hutool`、`android.util.Base64`、`com.jayway.jsonpath` 的等价实现。我们的 `JSCoreRuntime.swift`（287 KB）+ `LegadoHostServices.swift`（59 KB）覆盖面已经不小于它，差距主要在**长尾类名**，不在架构。

## 二、URL 层：Legado 语法对照

| Legado 行为（AnalyzeUrl.kt） | 我们的实现 | 状态 |
|---|---|---|
| `@js:` 整段求值，`result` 绑定原规则 | `SearchURLResolver.resolve` L73-91 | 已支持 |
| `<js>...</js>` 内嵌块 | 同上 L85-91 + `resolveEmbeddedBracesScripts` L211-224 | 已支持 |
| `{{任意表达式}}` 逐段求值 | `resolveEmbeddedBracesScripts` L226-279 | 已支持 |
| `@result` 把前面的字面量拼回结果 | 未实现 | 缺失（997 条里 0 条 searchUrl 使用） |
| `<1,2,3>` 页码分档，越界取最后一段 | `LegadoRuleResolver.replacePageAngles` L96-138 | 已支持 |
| `,{...}` URL 选项 | `SourceURLDirectiveParser` + `splitURLAndJSONOptions` L206-245 | 已支持（含单引号/尾逗号宽松解析） |
| `options.method` | `SourceURLDirective` L93-95 | 已支持 |
| `options.body`（字符串或对象） | L97-99 + `encodeBodyOption` L328-360 | 已支持 |
| `options.charset` | L101 + `SearchURLResolver.charset` L419-433 | 已支持 |
| `options.headers` | L91 + `parseHeaders` L199-230 | 已支持 |
| `options.retry` / `webView` / `webJs` | L110-118 | 已支持 |
| `options.js`：对最终 URL 求值并替换 | 只解析进 `SourceURLDirective.urlJavaScript`，无消费者 | **缺失** |
| `concurrentRate` 并发限速 | 全项目 0 处引用 | **缺失** |
| GET 查询串 / POST 表单字段级编码 | `SourceRequestBuilder` `KeywordEncoding` + `interpolateBodyText` | 已支持 |

## 三、规则层：997 条源的实际语法分布

### 3.1 `ruleSearch.bookList`

| 形态 | 数量 | 占比 |
|---|---|---|
| CSS / Legado 默认语法（`.bookbox`、`class.x@tag.li`） | 811 | 81.3% |
| JSONPath（`$.data[*]`） | 98 | 9.8% |
| `\|\|` 多规则组合 | 43 | 4.3% |
| `@js:` / `<js>` | 24 | 2.4% |
| XPath（`//div[...]`） | 10 | 1.0% |
| `@css:` 前缀 | 7 | 0.7% |
| `##` 正则 | 1 | 0.1% |

### 3.2 目录与正文

| 字段 | 主要形态 |
|---|---|
| `ruleToc.chapterList` | CSS/Legado 796、JS 72、JSONPath 58、XPath 26、`\|\|` 16 |
| `ruleToc.nextTocUrl` | CSS/Legado 87、`\|\|` 42、JS 24 |
| `ruleContent.content` | CSS/Legado 773、JS 90、JSONPath 57、模板 28 |
| `ruleBookInfo.tocUrl` | CSS/Legado 304、JS 51、模板 45、JSONPath 6 |

### 3.3 源级能力使用率

| 能力 | 使用源数 | 我们 |
|---|---|---|
| `header` | 237 | 已支持 |
| `searchUrl` 带 URL 选项 | 220 | 已支持 |
| POST 搜索 | 162 | 已支持 |
| `loginUrl` | 107 | 1.0.74 起支持 `loginUi` 表单 + 页面登录 |
| 搜索 URL 含 JS | 66 | 已支持 |
| `bookUrlPattern` | 212 | 已支持 |
| `loginUi` | 13 | 1.0.74 已支持 |
| `concurrentRate` | 5 | **缺失** |
| `loginCheckJs` | 4 | 已支持 |

## 四、"搜索为空"的归因顺序

按真实请求结果，排查顺序应是：

1. **连接层**：DNS / TLS / 502 / 403。997 条里大量老源已经死站，这类占抽样失败的一半以上。
2. **编码层**：`charset: gbk` 的 77 条源，关键字必须按 GBK 编码。我们走 `LegadoRuleResolver.encodeKeyword`，已对齐。
3. **请求形态层**：162 条 POST 源，body 模板必须按表单编码；JSON body 必须保留原样。1.0.72 已修。
4. **选项层**：19 条源用单引号 JS 对象写选项（`{'method':'POST'}`），严格 JSON 解析会整段丢弃。`SourceURLDirective` 的宽松解析已覆盖。
5. **选择器层**：JSONPath 98 条 + `||` 43 条 + XPath 10 条，是剩余失败的主要来源。
6. **渲染层**：15 条 `webView` 源必须走 WebKit，普通 HTTP 拿不到结果。

## 五、本轮新增：真实源回归集

`SourceReadSwiftTests/Fixtures/real-sources/` 收录了 12 条**当天真实可用**的源响应（byte-for-byte），配套 `RealSourceSearchRegressionTests`：

- 8 条 HTML 源：错层小说、错层小说网、精华书阁、笔趣阁[biquge7]、看书网、开心文学网、阅友小说、茶马小说
- 4 条 JSON API 源：松鹤阅读（带过滤器的 JSONPath）、中文万维、起步新榜、免费追书
- 每条 fixture 带 `expectedMinimum`，等于同一套规则在 Legado 语义下的命中数
- 断言方式：解析结果行数不得少于 `expectedMinimum`；失败时输出源名、实际行数、首本书名

这套测试的价值：**它第一次把"真实站点返回"接进了 CI**。以后任何解析器改动如果打坏了某个真实源的 bookList/name/bookUrl 提取，CI 会直接指出来源名。

## 六、1.0.75 待办

| 优先级 | 项 | 说明 |
|---|---|---|
| P1 | 真实源回归集接入 CI | 本轮已落地，等 CI 结果 |
| P1 | `options.js` 消费 | `SourceURLDirective.urlJavaScript` 传到请求层并执行 |
| P2 | JSONPath 过滤器覆盖 | `$.data.state[?(@.dataName == 'x')].items[*]` 已在 fixture 中 |
| P2 | `concurrentRate` | 按源 key 的令牌桶 |
| P3 | `@result` | 长尾 |
