# Legado 规则语法对照表（1.0.86）

对照依据：用户提供的 Legado 语法说明（jsoup / CSS / XPath / JSONPath / JS / AllInOne / OnlyOne / `&&` `||` `%%` / `@put` `@get` / URL 选项 / `{{}}` / `<>` 页码）。
结论：除「列表级 AllInOne `:regex`」外，语法均已落地并有回归测试。

## 一、选择器与取值

| 语法 | 实现 | 测试 | 状态 |
|---|---|---|---|
| Default `class.x.0@tag.a.0@text` | `LegadoDefaultRuleTranslator`、`HtmlRuleExtractor.select` | `LegadoDefaultRuleTranslatorTests`、`HtmlRuleExtractorTests` | 支持 |
| 负索引 `-1`、排除 `!0`、区间 `0:2`、步长 | `LegadoDefaultRuleTranslator.parseIndexItems` | `LegadoIndexSyntaxTests`（含 `li!0:1:2:3:4`） | 支持 |
| 列表倒序前缀 `-` | `HtmlRuleExtractor.select` / `ChapterListParser` | `LegadoIndexSyntaxTests`、`ChapterListMetadataTests.testReverseTocFlagReversesCollectedChapterList` | 支持 |
| CSS `@css:` | `HtmlRuleExtractor.cleanCSS` | `HtmlRuleExtractorTests` | 支持 |
| XPath `@XPath:`、`//` | `XPathRuleTranslator` | `HtmlRuleExtractorTests`（XPath 段） | 支持 |
| JSONPath `$.`、`@json:`、`$..`、`{$...}` 内联 | `JSONRuleExtractor` | `JSONRuleExtractorTests`、`JSONListDescendantTests` | 支持 |
| `@js:` / `<js></js>` / `+` 前缀 | `JSCoreRuntime`、`HtmlRuleExtractor` | `JSCoreRuntimeTests`、`LegadoJavaScriptCompatibilityTests` | 支持 |
| 净化 `##正则##替换`（循环） | `PurifyRuleEvaluator`、`RuleTransformParser` | `RuleTransformParserTests`、`HtmlRuleLegacyRegexTests` | 支持 |
| OnlyOne `##正则##替换###` | `RuleTransformParser.transform`（第 4 段即 replaceFirst） | `RuleTransformParserTests` | 支持 |
| `&&` 合并、`||` 取首个非空、`%%` 交错 | `RuleOperatorSplitter.firstOperator` | `RuleOperatorSplitterTests`、`HtmlRuleExtractorTests`、`JSONRuleExtractorTests` | 支持 |
| `@put:{k:rule}` / `@get:{k}`（含 JSONPath 不加引号） | `RuleDirectiveParser`、`RuleExecutionContext` | `HtmlRuleExtractorTests`、`JSONRuleExtractorTests`、`SourceEnginePersistentStateTests` | 支持 |
| **列表级 AllInOne `:正则`** | **未实现** | — | **缺口** |

## 二、URL 与模板

| 语法 | 实现 | 测试 | 状态 |
|---|---|---|---|
| `searchUrl` 相对 `bookSourceUrl` | `SearchURLResolver` + `SourceRequestBuilder.resolveURL` | `SourceSearchURLProbeTests`、`BookSourceTests.testRequestBuilderResolvesRelativeSearchURLWithLegadoOptions` | 1.0.86 修复 |
| `,{"method":"POST","body":...,"charset":"gbk","headers":...,"webView":true}` | `SourceURLDirective`、`SourceRequestBuilder` | `SourceURLDirectiveTests`、`SearchURLResolverTests` | 支持 |
| `{{key}}` / `{{page}}` / `{{(page-1)*20}}` | `LegadoRuleResolver.interpolate` | `SearchURLResolverTests` | 支持 |
| `<,{{page}}>` 页码角括号 | `LegadoRuleResolver.replacePageAngles` | `SearchURLResolverTests.testAngleBracketPaginationInSearchUrl` | 支持 |
| 搜索/发现 URL 内 `{{}}` 只跑 JS | `SearchURLResolver.resolveEmbeddedBracesScripts`（平衡扫描，支持对象字面量） | `SearchURLResolverTests.testMultiLineBraceBlockWithObjectLiteralIsEvaluated` | 支持 |
| 其他字段 `{{}}` 可放任意规则（`@@` / `@css:` / `@xpath:` / `$.`） | `HtmlRuleExtractor.interpolateTemplate` | `SourceFlowEngineTests`（`{{@css:...}}`） | 支持 |
| `{$.id}` 阅读 2.0 单花括号 | `JSONRuleExtractor.expandInnerJSONRules` | `JSONRuleExtractorTests` | 支持 |
| GBK/GB2312 关键字与响应解码 | `LegadoCharset`、`ResponseBodyDecoder` | `LegadoCharsetTests`、`ResponseBodyDecoderTests` | 支持 |

## 三、分阶段字段

| 阶段 | 已实现 | 测试 |
|---|---|---|
| 详情预处理 `ruleBookInfo.init`（正则 AllInOne 或 JS） | `BookDetailParser`（JS 返回对象会经 `JSON.stringify` 落成 JSON 容器） | `JSONPipelineParserTests.testParseJSONBookDetailRunsJSInitAgainstNonJSONBody` |
| 目录 `chapterList` / `chapterName` / `chapterUrl` / `isVip` / `updateTime` | `ChapterListParser` | `ChapterListMetadataTests` |
| 目录下一页 `nextTocUrl`（字符串或列表、`[]`/null 停止） | `ChapterListParser` 分页循环 | `ChapterListMetadataTests`（分页、卷名继承） |
| 正文 `content` / `nextContentUrl` / `webJs` / `sourceRegex` | `ContentParser`、`WebViewFallback` | `ContentParserTests`、`WebViewResourceSniffingTests` |
| `bookSourceType: 1` 音频/视频 | `VideoContentParser`、`ComicContentParser` | `VideoContentParserTests`、`ComicContentParserTests` |

## 四、唯一缺口：列表级 AllInOne `:regex`

文档【书源二】的目录规则：

```
"chapterList": ":href=\"(/read[^\"]*html)\">([^<]*)"
```

Legado 的语义是：对整页 HTML 跑正则，每个匹配产出一个条目，`$1` 为章节 URL、`$2` 为章节名；搜索/发现列表同理（`$1` 书籍 URL、`$2` 书名）。本项目当前把 `chapterList` 直接交给 `HtmlRuleExtractor.select`，`:` 开头会被当成 CSS 选择器而得到 0 条。

影响面：997 条语料中 `chapterList` / `bookList` 以 `:` 开头的数量为 **0**，所以现有源不受影响；只有手写源（含文档示例）会命中。

建议实现方式（下一轮）：

1. 新增 `LegadoAllInOneRegex`：解析可选 `-`/`+` 前缀与 `:pattern`，对 `body` 跑 `NSRegularExpression`，返回 `[[String]]`（每个匹配的捕获组）；
2. `ChapterListParser` 在 `listRule` 命中 `:pattern` 时走该分支：`url = group[1]`、`name = group[2]`，`-` 前缀反转；
3. `SearchResultParser` 同样处理 `bookList`，字段规则中的 `$1`/`$2` 直接取捕获组；
4. 用文档【书源二】的目录规则加 fixture 锁定。

## 五、结论

- 语法覆盖已完成，1.0.86 的探针修复解决的是「诊断误报」，不是引擎缺陷；
- 实测 994 条 `searchUrl`，URL 层缺陷 19 → 2，无回归；
- 剩余缺口只有列表级 AllInOne，语料命中 0，按上面的方案可在下一轮补齐。
