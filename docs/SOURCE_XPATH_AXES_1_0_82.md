# 1.0.82 — 书源 XPath 轴支持

## 背景

书源搜索 200 条采样里，`//dt[2]/following-sibling::dd/a`（biqusa）与
`//*[@class="chapter clearfix"]/a`（塔读）都返回 0 条。前者不是站点失效，
而是 `XPathRuleTranslator` 把 `following-sibling::` 丢掉了，规则退化成
`//dt[2]/a`，自然选不到兄弟节点下的链接。

## 改动

`SourceReadSwift/Core/Rules/XPathRuleTranslator.swift`：

| XPath 轴 | 翻译 |
|---|---|
| `following-sibling::` | CSS `~ ` |
| `child::` | `> ` |
| `descendant::` / `self::` | 组合符省略 |
| `parent::` / `ancestor::` / `preceding-sibling::` / `preceding::` / `following::` | 整条规则拒绝（返回 nil），不再静默丢步选错层 |

带轴规则里的位置谓词翻译为 `:nth-of-type(n)` / `:last-of-type`，
因此 `//dt[2]/following-sibling::dd/a` 不会丢掉中间步。
`*#id` / `*.class` 去掉 universal `*` 前缀，SwiftSoup 能直接命中。

## 测试

`SourceReadSwiftTests/HtmlRuleExtractorTests.swift` 新增：

- `testXPathFollowingSiblingAxisSelectsChapterRows`（biqusa 真实结构）
- `testXPathUniversalClassSelectorResolves`（`//*[@class="chapter clearfix"]/a`）
- `testXPathUnsupportedAxisIsRejectedInsteadOfDroppingSteps`

## 边界

- `parent::` / `ancestor::` 等向上轴 CSS 无法等价表达，选择整条拒绝而不是降级；
  这类源需要在后续版本用 DOM 选择器或 XPath 引擎补，不在本版假装支持。
- 尖括号 URL 语法（`{{key}}<,&p={{page}}>`）尚未处理，已记录在搜索采样报告里。
