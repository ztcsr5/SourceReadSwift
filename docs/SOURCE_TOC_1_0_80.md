# 目录（TOC）对账 1.0.80：97 条真实目录页

基线：`SourceReadSwiftTests/Fixtures/toc-corpus/`（97 条 manifest + 52 个真实 body，11.0 MB），
参考实现：jsoup-1.17.2 直接跑 Legado `chapterList` 规则（`LegadoCount.java`），
被测实现：Swift `HtmlRuleExtractor.select(_:baseUrl:listRule:)` + `value(from:rule:)`。

## 1. 语料怎么来的

1. 从 `all_book_sources.json` 里取 114 条在 rows 通道能出结果的源；
2. 用 `LegadoUrls.java` 跑真实的 `searchUrl` -> `bookUrl` -> `tocUrl` 链路，
   拿到 98 本书的详情页和 33 个独立目录页；
3. 修复 `text.<文本>@href` 未翻译（此前 `tocUrl` 为空）后，49/152/175/202 四条恢复取到目录 URL；
4. 对 97 条能拿到目录页的源，用 jsoup 跑 `chapterList` 计数，写入 `expected`；
5. 同一份 body 打进测试包，Swift 跑同样的规则，比较 `actual`。

## 2. 30 条 expected=0 的归因（不是 Swift bug）

`expected=0` 意味着 **jsoup 自己也选不到任何章节**。逐条看 body 后分四类：

| 归因 | 条数 | id | 证据 |
|---|---|---|---|
| `SITE_DEAD`：站群统一返回「糟糕,页面找不到了」错误页 | 15 | 202, 845, 849, 851, 853, 864, 865, 878, 904, 906, 915, 923, 976, 978, 979 | body 全是同一份 2395 字节错误页，`<meta http-equiv="refresh" content="5;url=http://book.sfacg.com/">` |
| `RULE_STALE`：站点改版，规则里的 class/id 在页面上不存在 | 5 | 573（无 `class=list`）、259（无 `chapter clearfix`）、451（无 `id=list`）、873/902（无 `list-inline-3`，且抓到的是首页） | body 里目标 class/id 计数为 0 |
| `NEED_JS`：chapterList 本身是 JS / JSONPath 规则 | 6 | 49, 112, 117, 151, 446, 745 | 规则含 `@js:`、`<js>`、`$..chapters[*]` |
| `RULE_MISMATCH`：JSON 规则套在 HTML 页面上 | 3 | 908, 955, 960 | 规则是 `items`（JSON 数组），body 是 10 KB HTML |
| `NEED_JS`/URL：抓到的详情页本身没有章节列表 | 1 | 119 | 页面只有 `comics-detail`，`comics-chapters__item` 计数 0，章节靠前端渲染 |

**结论：这 30 条不是解析器缺陷。** 它们说明书源生态里约三成源已经失效或依赖 JS；
App 端要做的是「快速归因 + 明确提示」，而不是继续在 CSS 选择器上打补丁。

## 3. 67 条 expected>0 的对账结果

（probe 跑完后填：`TOC_CORPUS total=97 mismatches=N`，差异逐条列 `expected/actual/rule`，
并区分「选择器差异」与「字段差异」——`emptyNames` / `emptyURLs`。）

## 4. 字段级检查

probe 同时统计前 5 章的 `chapterName` / `chapterUrl` 是否为空：
`TOC_FIELDS emptyNames=… emptyURLs=…`。空名字通常是 `chapterName` 用了 `text.` 之外的
属性（如 `@title`）或节点本身是 `<a><span>…</span></a>`；空 URL 通常是相对路径没吃到 `baseUrl`。

## 5. 下一步

- 把 `XPathRuleTranslator` 的 `following-sibling::` / `//` 语义补齐（451、259 这类源）；
- 对 `items` 规则的源，tocUrl 返回 JSON 时走 `JSONRuleExtractor`，不要强塞 HTML 通道；
- 源诊断面板直接复用这四类归因，用户点「测试书源」就能看到 `SITE_DEAD` / `RULE_STALE` / `NEED_JS`。
