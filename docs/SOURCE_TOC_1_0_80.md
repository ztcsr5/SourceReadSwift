# 目录（TOC）对账 1.0.80：97 条真实目录页

基线：`SourceReadSwiftTests/Fixtures/toc-corpus/`（97 条 manifest + 51 个真实 HTML，11.0 MB），
参考实现：jsoup-1.17.2 直接跑 Legado `chapterList` 规则（`LegadoCount.java`），
被测实现：Swift `HtmlRuleExtractor.select(_:baseUrl:listRule:)` + `ChapterListParser`。

## 1. 语料怎么来的

1. 从 `all_book_sources.json` 里取 114 条在 rows 通道能出结果的源；
2. 用 `LegadoUrls.java` 跑真实的 `searchUrl` -> `bookUrl` -> `tocUrl` 链路，
   拿到 98 本书的详情页和 33 个独立目录页；
3. 修复 `text.<文本>@href` 未翻译（此前 `tocUrl` 为空）后，49/152/175/202 四条恢复取到目录 URL；
4. 对 97 条能拿到目录页的源，用 jsoup 跑 `chapterList` 计数，写入 `expected`；
5. Swift 用同一份 HTML 跑同样的规则，比较 `actual`，并抽样前 5 章检查章节名与 URL。

## 2. 30 条 expected=0 的归因（不是 Swift bug）

`expected=0` 意味着 **jsoup 自己也选不到任何章节**。逐条看 HTML 后分四类：

| 归因 | 条数 | id | 证据 |
|---|---|---|---|
| `SITE_DEAD`：站群统一返回「糟糕,页面找不到了」错误页 | 15 | 202, 845, 849, 851, 853, 864, 865, 878, 904, 906, 915, 923, 976, 978, 979 | 全是同一份 2395 字节错误页，`<meta http-equiv="refresh" content="5;url=http://book.sfacg.com/">` |
| `RULE_STALE`：站点改版，规则里的 class/id 在页面上不存在 | 5 | 573（无 `class=list`）、259（无 `chapter clearfix`）、451（无 `id=list`）、873/902（无 `list-inline-3`，且抓到的是首页） | HTML 里目标 class/id 计数为 0 |
| `NEED_JS`：chapterList 本身是 JS / JSONPath 规则 | 6 | 49, 112, 117, 151, 446, 745 | 规则含 `@js:`、`<js>`、`$..chapters[*]` |
| `RULE_MISMATCH`：JSON 规则套在 HTML 页面上 | 3 | 908, 955, 960 | 规则是 `items`（JSON 数组），body 是 10 KB HTML |
| `NEED_JS`/URL：抓到的详情页本身没有章节列表 | 1 | 119 | 页面只有 `comics-detail`，`comics-chapters__item` 计数 0，章节靠前端渲染 |

**结论：这 30 条不是解析器缺陷。** 它们说明书源生态里约三成源已经失效或依赖 JS；
App 端要做的是「快速归因 + 明确提示」，而不是继续在 CSS 选择器上打补丁。

## 3. 67 条 expected>0 的对账结果

probe run `40629754410`（commit `b5014be`）：

```text
TOC_CORPUS total=97 mismatches=0
TOC_FIELDS emptyNames=9 emptyURLs=9
```

- **选择器 97/97 与 jsoup 完全一致**：30 条 0、67 条正数（min 1、median 500、max 3254）。
- 字段级：67 条源各抽前 5 章，共 335 行，其中 9 行章节名/URL 为空，集中在 4 条源：

| id | 源 | 现象 | 归因 |
|---|---|---|---|
| 57 | 茶马小说 | 5/5 章名与 URL 空 | `<option value="…">标题</option>` 目录，默认 `a@href` 读不到 → **解析器缺口，已修** |
| 141 | 商店小说 | 2/5 空，首条是作者名「陌文子」 | `class.row@li` 抓到推荐位 → 规则过时 |
| 159 | 吾爱破解 | 1/5 空 | `chapterList: tag.h1` 本身不是目录规则 → 规则错误 |
| 891 | 潇湘书院 | 1/5 空 | `.profile-main li` 混入导航行 → 规则过时 |

修复：`ChapterListParser.makeChapter` 在 `href` 为空且元素是 `<option>` 时读 `value`；
单测 `ChapterListParserTests` 之外的 `ChapterListMetadataTests.testSelectOptionTOCUsesValueAttributeForChapterURL` 覆盖该路径。

## 4. 字段级检查的语义

源不写 `chapterName` / `chapterUrl` 时，Legado 用行文本与 `href` 作为默认；
`makeChapter` 的 fallback 也是这个语义（`a@text` / `a@href`，再退到元素自身）。
probe 早期版本把空字符串当规则传，导致 301 行误报——**那是探针的问题，不是产品的问题**；
现在 probe 与 `makeChapter` 走同一条 nil-rule + fallback 路径。

## 5. 下一步

- 重跑 probe，确认 57 号 5 行归零（预期 `emptyNames=4`）；
- `XPathRuleTranslator` 补 `following-sibling::` 语义（451、259 这类源，当前站点已失效但语法缺口真实存在）；
- 对 `items` 规则的源，tocUrl 返回 JSON 时走 `JSONRuleExtractor`，不要强塞 HTML 通道；
- 源诊断面板复用这四类归因：`SITE_DEAD` / `RULE_STALE` / `NEED_JS` / `RULE_MISMATCH`。
