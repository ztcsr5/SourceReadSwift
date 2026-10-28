# 书源 row 对账 1.0.79（114 条真实搜索响应）

基线：`SourceReadSwiftTests/Fixtures/rows-corpus/`（114 个真实 body + manifest），
参考实现：jsoup-1.17.2（Legado `AnalyzeByJSoup` 使用的选择器语义），
被测实现：Swift `HtmlRuleExtractor.select(_:baseUrl:listRule:)`。

## 1. 首轮结果（1.0.77 probe，run 40621875813）

`total=114 mismatch=5 zero-actual=0` —— 没有一条「规则匹配但 Swift 选 0 条」，
说明 1.0.77 的 URL/解码/选择器主链路是通的；差异全部是**多选**。

| id | 书名/源 | 规则 | 参考 | Swift | 结论 |
|---|---|---|---|---|---|
| 498 | 顶点小说 | `id.nr` | 1 | 50 | 真 bug：`#id` 返回全部同名 id，Legado 用 `getElementById` 只取第一个 |
| 141 | 商店小说 | `class.col-12 col-md-6` | 17 | 18 | 真 bug：jsoup `getElementsByClass` 按「连续 token 段」比较 class 属性 |
| 525 | 星星小说 | `class.col-12 col-md-6` | 17 | 18 | 同上 |
| 451 | 笔趣小说 | `class.novelslist2@ul@li[1:3]` | 2 | 3 | 参考端 bug：Legado `[1:3]` 是**闭区间**（3 条） |
| 975 | 未来天王 | `.novelslist2 li[1:-1]` | 2 | 100 | 参考端 bug：101 个 `li` 的闭区间 `1:-1` = 100 条 |

## 2. jsoup 语义验证（本地 java + jsoup-1.17.2 实测）

```
byClass("col-12 col-md-6") = 2     // 三个 div：两个 class 完全一致、一个中间夹 col-sm-9
select(".col-12.col-md-6")  = 4     // CSS 形式会多选，不能用来翻译 class. 规则
select("#nr")               = 3     // #id 返回全部同名
getElementById("nr")        = 首个  // Legado 走这条
```

## 3. 修复

- `LegadoRuleStep.classToken`：`class.` 名字含空格时不再翻译成 `.a.b`，改由
  `matchesClassToken` 按「class 属性中的连续 token 段」过滤；
- `id.` 前缀在无显式索引时补 `.single(0)`，等价 `getElementById`；
- 基线 `LegadoCount.java` 的索引解析改为 Legado 的闭区间语义（`[1:3]`、`[1:-1]`），
  重新跑 114 条后只有 451/975 两个 `expected` 变化，其余 112 条逐字节一致 → 说明
  改的是基线的表达力，没有改动其它规则的结果。

## 4. 单测

`HtmlRuleExtractorTests`：
- `testIdPrefixTakesTheFirstMatchLikeGetElementById`
- `testClassRuleWithSpacesMatchesOneContiguousTokenRun`

## 5. 结论边界

对账只覆盖 **rows（列表条数）**。`name/author/cover/intro` 的逐字段一致性、
分页 `nextPage`、以及需要 JS 的书源（`@js:` / `{{}}`）不在本对账范围内，
下一轮用同一 corpus 扩字段对比。
