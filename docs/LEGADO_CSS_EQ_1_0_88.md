# `:eq(n)` 语义修正与 TOC 基线校准（1.0.88）

日期：2026-10-28  
版本：1.0.88 (Build 89)  
分支：`codex/reader-feedback-fixes`

## 一、问题：`@css:` 的 `:eq(n)` 被当成列表索引

Legado 语法说明与真实书源里，CSS 规则使用 jsoup 的 `:eq(n)`：

```
@css:.itemtxt p:eq(1) a@text
@css:.itemtxt ul li:eq(0) a@text
@css:.itemtxt p:eq(0) span:eq(1)@text
@css:.prenext span:eq(2) a@href
```

jsoup 语义：`:eq(n)` 是 **0-based、在每个父元素内部**的同类子元素索引。  
旧实现：`LegadoDefaultRuleTranslator.parseSingleStep` 与 `HtmlRuleExtractor.parseIndexedSelector` 会把结尾的 `:eq(n)` 剥离成「对整个匹配结果取第 n 个」。

两个语义只在「只有一个父元素」时等价；列表页有多个父元素时，旧实现只保留一条结果，其余行字段为空。真实源「速读谷」的 `ruleSearch` / `ruleBookInfo` / `ruleContent` 共 4 处命中该形态。

## 二、修复

- `LegadoDefaultRuleTranslator.translateSelectorSteps(_:cssSemantics:)`：显式 `@css:` / `css:` 规则不再剥离 `:eq(n)`，交给 SwiftSoup 原生选择器；
- `HtmlRuleExtractor.parseIndexedSelector(_:stripCSSEq:)`：同上，显式 CSS 不把 `:eq(n)` 当列表索引；
- Default 规则（`class.x.0@tag.a.0@text`）行为不变，索引仍走 Legado 列表语义。

## 三、回归

`SourceReadSwiftTests/HtmlRuleExtractorTests.swift` 新增两条：

- `testExplicitCSSEqKeepsPerParentSemantics`：两个 `.item`、每个 3 个 `p`，`@css:.item p:eq(1)>a@text` 必须返回 `["a1", "b1"]`（旧实现返回 `["a1"]`）；
- `testExplicitCSSTailEqIsNotTreatedAsListIndex`：`@css:.item p:eq(1)@text` 同样返回两条。

## 四、TOC 基线校准（id 451 笔趣小说）

`toc-probe` 97 条中唯一 mismatch：

| 字段 | 值 |
|---|---|
| id | 451 |
| 源 | 笔趣小说 |
| 规则 | `//*[@id="list"]//dt[2]/following-sibling::dd/a` |
| 旧 expected | 0 |
| actual | 1914 |
| emptyNames / emptyURLs | 0 / 0 |

同一个 `toc-e90ddf69aa9c.html`（198,572 字节）：

- 页面结构：`<div id="list">` 内 2 个 `<dt>`、1,926 个 `<dd>`；`dt[1]` 后 12 条「最新章节」，`dt[2]` 后 1,914 条正文目录；
- Swift 探针：1,914 条，首条 `第一章 陨落的天才`，末条 `第一千五百九十三章 古帝洞府所在`；
- 独立复核 `lxml` 同一 XPath：1,914 条，首个 href `/76_76571/31545538.html` 与 Swift 一致。

结论：`expected: 0` 是 jsoup 基线采集时该次页面未返回目录（或 JsoupXpath 对 `following-sibling` 轴处理异常）留下的错误基线，解析器本身正确。`manifest.json` 已把 451 的 `expected` 更新为 1914。

## 五、不改变的边界

- 未修改任何 TOC/搜索解析逻辑来「凑」0；
- rows-probe 114 条仍为 0 mismatch；
- TOC 的 29 条 0 命中维持 1.0.80 归因（站点失效 15 / 规则过时 5 / JS 6 / JSON 错配 3），非本轮回归。
