# CODEX 交接 — v1.0.67 (Build 68)

> **分支**：`codex/reader-feedback-fixes`
> **提交**：`1fe7d6d`（`fix(reader): hang CJK punctuation on the line that owns it`）
> **日期**：2026-10-28
> **上一版**：v1.0.66 (Build 67) / `f9032bb`
> **本轮输入**：用户确认「可以就用 TextKit，现在就是细节问题」，并追问 iOS 侧有没有可参考的开源实现

---

## 一、本轮只做一件事：中文标点不再落到行首

| 项 | 内容 |
|---|---|
| 症状 | 正文里 `。，、）」` 等标点出现在行首，段落看起来参差 |
| 根因 | `NSParagraphStyle.lineBreakStrategy` 默认 `.standard`；TextKit 1 的默认策略只保证西文单词边界，不保证 CJK 行首禁则 |
| 修复 | 统一使用 `.pushOut`：标点悬挂在上一行行尾，不另起一行 |
| 关键约束 | 分页测量（`ReaderPageLayoutEngine.lineMetrics`）与渲染（`ReaderPageTextBuilder`）必须读同一个策略；两边不一致时「量一页、画另一页」 |

### 1.1 代码落点

```swift
// ReaderPageLayoutEngine.swift
static let lineBreakStrategy: NSParagraphStyle.LineBreakStrategy = .pushOut

// lineMetrics 内
style.lineBreakMode = .byWordWrapping
style.lineBreakStrategy = lineBreakStrategy

// ReaderPageTextView.swift — 标题与正文两处
titleStyle.lineBreakStrategy = ReaderPageLayoutEngine.lineBreakStrategy
paragraphStyle.lineBreakStrategy = ReaderPageLayoutEngine.lineBreakStrategy
```

### 1.2 为什么不是 `.hangulWordPriority` / `.standard`

- `.standard`：默认行为，CJK 标点会被推到下一行行首，正是本轮要修的现象。
- `.pushOut`：把行尾禁则标点外挂到行末，行宽可能略微溢出容器；这是中文排版期望的行为。
- 该策略只影响断行点，不改变字号、行距、段距，因此不会推翻 1.0.65/1.0.66 的排版基线。

---

## 二、测试

新增 3 条断言（`SourceReadSwiftTests/ReaderPageTextBuilderTests.swift`、`ReaderPageLayoutEngineTests.swift`）：

| 测试 | 断言 |
|---|---|
| `testBodyAndTitleUsePushOutLineBreakStrategy` | 标题与正文的 `paragraphStyle.lineBreakStrategy == .pushOut` |
| `testMinimumAndMaximumLineHeightStayUnset` | 两者保持 0，避免覆盖字体自然行高、与 `measureHeight` 分叉 |
| `testLineBreakStrategyIsPushOut` | 分页引擎常量固定为 `.pushOut` |

测试口径：测量与渲染同策略；若未来只改一侧，`testBodyAndTitleUsePushOutLineBreakStrategy` 会先失败。

---

## 三、构建与产物（真实执行）

| 项 | 值 |
|---|---|
| 代码提交 | `1fe7d6d7fea8867e3c7b28f9bf06f7a9ec23775b` |
| iOS CI run | `40574160264`（job `122435994785`）— **success** |
| 测试 | **Executed 1115 tests, with 0 failures**；`** TEST SUCCEEDED **` |
| IPA CI run | `40574160301` — **success** |
| IPA artifact | `12766692606`（`SourceReadSwift-unsigned-ipa`，12,088,576 B zip） |
| 本地 IPA | `C:\Users\Edc21\Desktop\SourceReadSwift-1.0.67-unsigned.ipa`（12,182,094 B） |
| SHA256 | `C671EC2CE5853DD6F4BF955ACB39F4E2558CA54FC79D753FB168CA5838FACA52` |
| 版本校验 | `CFBundleShortVersionString 1.0.67` / `CFBundleVersion 68` / `MinimumOSVersion 16.0` |

---

## 四、未做与下一步（按证据缺口排序）

| # | 项 | 现状 | 下一步 |
|---|---|---|---|
| 1 | 段间距 < 行距 | 默认 `lineSpacing 12` / `paragraphSpacing 10`（20pt 正文） | 调整为段距 > 行距（如 8 / 16），同步 `ReaderTypographyDefaults` 与测试 |
| 2 | 章节标题在页眉与正文内重复 | `chapterHeadingStyle` 默认 `.header`，部分书源标题仍进正文 | 统一标题来源：页眉只显示章名，正文只在章首页渲染标题块；去重 |
| 3 | 对齐方式 | 正文 `.justified`，标题 `.natural` | 真机比对竞品；若 `pushOut + justified` 出现行尾空洞，改 `.natural` 或调 `hyphenationFactor` |
| 4 | iOS 16 真机 | 代码级兼容已做（`contentInsetAdjustmentBehavior = .never`、固定提案尺寸） | 明天真机跑：分页顶部留白、三模式起手、章边界重绘 |
| 5 | 视觉验收 | 本轮只有 CI 证据 | 真机截图对比「标点是否悬挂、行尾是否溢出 1–2pt」 |

---

## 五、事实标记

- `Observed`：代码、测试、CI 日志、IPA plist 与 SHA256 均为真实执行结果。
- `Inferred`：`.pushOut` 消除行首标点的机制判断（TextKit 1 行为）。
- `Assumed`：真机上标点悬挂后的行宽溢出在 1–2pt 内、不触发额外换行 —— 待真机截图验证。
