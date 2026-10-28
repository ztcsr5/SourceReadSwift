# SourceReadSwift 1.0.98 交接记录

日期：2026-10-29
基线：1.0.97 (98) → 1.0.98 (99)
分支：`codex/reader-feedback-fixes`（推送 `codex/swift-v2-lifetime-reader`）

## 1. 本轮修复的四个阅读器/搜索问题

### 1.1 iOS 16 正文双引号行不对齐

**现象**：iOS 16 上，含全角标点的两端对齐行末字到不了右边距（实测 828px 宽截图里差 19–23px，约 0.4 个汉字），iOS 17 正常。同一章在 iOS 16 上字距也被拉得很散。

**根因**：iOS 17 起 CoreText 在两端对齐时会做「标点挤压」——把 `，。；：` 和后引号、后括号的右侧空白收掉；iOS 16 不做，全角标点仍然占满一个 em，行末标点的墨迹停在半个字宽处，整行看起来短了一截。我们代码里 `.pushOut` 行断策略两个系统都开了，差异来自 CoreText 版本，不是规则配置。

**改动**（新文件 `SourceReadSwift/Features/Reader/ReaderCJKPunctuationCompression.swift`）：

- 对正文字符串逐字加负 `.kern` 复刻 iOS 17 的挤压量：`，。、；：` 与后引号/后括号 −0.5em，`！？` −0.25em；标题不加。
- 三处调用，测量与绘制必须同参：
  - `ReaderPageTextBuilder.make`（分页模式绘制）
  - `ReaderPageLayoutEngine.lineMetrics`（分页测量，仅 `.justified`）
  - `NativeReaderTextView` 的 `makeAttributedText` / `makeAttributedChunk`（滑动模式）
- 顺带给滑动模式的段落补上 `lineBreakStrategy = .pushOut`，与分页引擎一致，避免行首出现 `。，）`。

**单测**：`ReaderPageTextBuilderTests.testCJKPunctuationIsCompressedLikeIOS17`、`testTitleIsNotPunctuationCompressed`。

**边界**：这是排版近似，不是逐像素复刻 iOS 17 的 CoreText；iOS 16 真机效果待用户实测。

### 1.2 阅读器底部菜单过宽、留白多、半透明

`ReaderView.swift` 底部面板原来是「内层 14pt + 外层 14pt = 28pt 边距 + `readerThemeBackground.opacity(0.96)` + `.glassPanel(.ultraThinMaterial)`」。material 叠在主题色上，面板始终是半透明，且比顶部栏宽。

改为与顶部栏完全同构：内层 10pt、外层 16pt、`opacity(0.97)` 单层不透明底、圆角 18、0.6pt 描边、纯阴影，移除 `glassPanel`。

### 1.3 搜索页点空白无法收起键盘

新增 `View.dismissKeyboardOnTap()`（`AppTheme.swift`，`simultaneousGesture(TapGesture)`），挂在发现页 ScrollView 上；回车提交时也主动 `dismissKeyboardNow()`。结果行、筛选 chip 的点击不受影响。

### 1.4 键盘弹起时顶部导航跟着上移

`DiscoverView` 的 ScrollView 加 `.ignoresSafeArea(.keyboard, edges: .bottom)`，键盘不再压缩滚动视图，搜索框与页签保持原位，键盘直接覆盖下半部分。

## 2. 书源链路实测（LAN，iPhone 192.168.31.205:8080）

`GET /api/status` → `sourceCount=992 enabledSourceCount=991`。

用 `/api/source/debug`（真机引擎，step=search，关键词「剑来」）抽样 40 条以 Legado 旧语法为主的源（`@tag`、`<js>`、`class.`、`id.`）：

| 结果 | 数量 | 说明 |
|---|---|---|
| PASS | 35 | 搜索返回 30–100 条 |
| FAIL 站点侧 | 3 | 八一中文 DNS 不通；无极小说 TLS 握手失败；笔尖中文上游 502 |
| FAIL 解析侧 | 2 | 唔爱书包 / 爱书不包（同站 ishubao.org）：命中列表但书名链接为空 |

单条 `20小说网`（`https://www.20xs.org/`）单独复查：站点对搜索 POST 直接返回「错误提示」页，属站点侧，不是解析器问题。

结论：旧语法源的主体解析链路可用；剩下的失败集中在站点存活与个别站点改版，未发现新的引擎级通用缺陷。

## 3. 未执行 / 待验证

- iOS 16 真机：标点挤压后的行末对齐、字距观感（用户次日实测）。
- 全量 992 源复测：本轮只抽样 40 条，NOT RUN。
- 唔爱书包个别失败的规则细节：NOT RUN（站点是否改版未确认）。
- CI：见提交记录，iOS 测试 + Unsigned IPA 两条流水线。
