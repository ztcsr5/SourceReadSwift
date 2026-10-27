# CODEX 交接 — v1.0.68 (Build 69)

> **分支**：`codex/reader-feedback-fixes`
> **提交**：`eae2e94`（`fix(reader): put paragraph spacing above line spacing and dedupe numeric headings`）
> **日期**：2026-10-28
> **上一版**：v1.0.67 (Build 68) / `1fe7d6d`
> **本轮输入**：用户追问「1、2 你前面不是改过了吗」——确认 1.0.65 改过，但只解决了「从无到有」，比例与匹配边界没到位

---

## 一、1.0.65 改了什么，为什么仍然不达标

| 项 | 1.0.65 的做法 | 残留问题 |
|---|---|---|
| 段间距 | `paragraphSpacing 0 → 10`，行距保持 12 | **段距 10 < 行距 12**，违反「段间距要比行间距大」的排版常识；用户看到的仍是「段落粘在一起」 |
| 标题去重 | `comparisonKey` 去掉空白/标点后比较；前缀差 ≤ 6 字才剥 | 目录用中文数字、正文用阿拉伯数字（`第八章` vs `第8章`）时 key 不同，不剥；`（本章完）` 等后缀超过 6 字也不剥 |

结论：不是重复劳动，而是把两条改到「参数正确 + 匹配覆盖真实书源方言」。本轮只动这两个点，不碰分页与翻页逻辑。

---

## 二、段间距：8 / 16

```swift
// ReaderTypographyDefaults
static let lineSpacing: Double = 8       // 行内额外 leading
static let paragraphSpacing: Double = 16 // 段后距 = 2 × 行距
```

- 与 RSS 正文一直使用的 `8 / 16` 对齐，同一条排版基线。
- 分页测量与渲染同源：`appendPages` 的 `currentHeight += spacing + wholeHeight` 与 `ReaderPageTextBuilder` 的 `paragraphSpacing` 使用同一个 `ReaderTypographyDefaults.paragraphSpacing`，改默认值不会出现「量一页、画一页溢出」。
- 迁移键 `reader.typographyMigrated.v66`：**只**把 1.0.65 的旧默认 `12 / 10` 改写为 `8 / 16`；用户手动调过的值不动。
- 一键排版预设 `applyCompetitiveReaderPreset` 的 `lineSpacing` 改为读取默认值，不再硬编码 12。

---

## 三、标题去重：按「标题核心词」比较

新增 `ChapterTextSanitizer.headingCoreKey`：

1. 去掉开头的 `第X章 / 节 / 回 / 卷 / 部 / 篇 / 集`（X 支持中文数字与阿拉伯数字）；
2. 去掉括号注释 `（…）`、`(…)`、`【…】`、`[…]`；
3. 去掉常见站点后缀：`最新章节`、`求月票`、`求推荐`、`求收藏`、`本章完`、`正文`；
4. 再走原有 `comparisonKey`（去空白、标点、宽度折叠）。

比较规则：

- 两边 core 相等 → 剥；
- 一边是另一边前缀且剩余 ≤ 12 字 → 剥；
- **标题只有标记**（如 `第8章`）时 core 为空，退回 `comparisonKey` 两侧比较，保证 `第8章` vs `第8章 入城` 仍能剥。

标题形状识别放宽：新增 `1. 风起`、`12、入城`、`卷一 风起`，这些源没有 `第/章` 也能从正文回填标题。

---

## 四、测试

| 文件 | 新增 |
|---|---|
| `ChapterTextSanitizerTests` | 数字风格差异、括号后缀、长段落不误删、`1. 风起` 回填、标题仅标记 |
| `ReaderSettingsModelsTests` | 默认 8 / 16 + `paragraphSpacing > lineSpacing` 断言 |

测试口径：段距必须大于行距；标题去重不能误删以标题词开头的正常长段落。

---

## 五、构建与产物（真实执行）

| 项 | 值 |
|---|---|
| 代码提交 | `eae2e94ef36878a0e28a66534766ed78c5267886` |
| iOS CI run | `40581829580`（job `122462948434`）— **success** |
| 测试 | **Executed 1120 tests, with 0 failures**；`** TEST SUCCEEDED **` |
| IPA CI run | `40581829363` — **success** |
| IPA artifact | `12770388244`（12,089,507 B zip） |
| 本地 IPA | `C:\Users\Edc21\Desktop\SourceReadSwift-1.0.68-unsigned.ipa`（12,182,597 B） |
| SHA256 | `493373C174C128B9F8DF87914EFF246B37CD64844CE6654D5CC3FBAFD234FC64` |
| 版本校验 | `1.0.68` / `69` / `MinimumOSVersion 16.0` |

---

## 六、未做

- 真机视觉验收：段距 16pt 在 20pt 正文下的密度、标题去重后章首页是否仍有双标题（需要具体书名 + 源）。
- 对齐：正文仍 `.justified`；`pushOut` 与 justify 组合的行尾空洞待真机截图。
- iOS 16 真机矩阵：明天执行。

---

## 七、事实标记

- `Observed`：代码、测试、CI 日志、IPA plist 与 SHA256。
- `Inferred`：`headingCoreKey` 覆盖的中文书源方言（第八章/第8章、括号后缀）。
- `Assumed`：8 / 16 的密度在真机上舒适——需要用户真机确认，代码侧只保证「段距 > 行距」。
