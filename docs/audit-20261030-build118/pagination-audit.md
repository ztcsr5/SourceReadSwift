# Build 118 分页、缓存与正文完整性审查

审查基线：Git HEAD `5686485`；build 118 `bffedba`；build 117 `771d2e4`。日期：2026-10-30。仅新增审查文档和独立模型，未改业务代码。

## 结论

问题并非只差几个 pt 的底部留白。当前存在 **分页模型、富文本缓存、页面控制器和位置锚点四套不同的“版本/身份”定义**。最优先问题是页面富文本缓存没有几何/正文版本，重分页后可以显示旧正文；章节缓存又只看首尾段，正文中段刷新不会失效。118 增加底部缓冲并不能修复这些完整性问题。

证据标记：`Observed` = 源码或已执行的逻辑模型直接证明；`Inferred` = 可从调用路径推导的用户症状，未在设备重现；`NOT RUN` = 未执行。Windows 环境未运行 Xcode、Swift/UIKit、iOS 模拟器；本文绝不把 Python 模型当作真机验收。

## 1. P1 — 重分页后的富文本 key 不变，可显示旧文本分片

**Observed**

- `SourceReadSwift/Features/Reader/ReaderPageSelection.swift:10-20,30-32`：页面身份只含 chapterIndex、pageOrdinal、firstParagraphIndex、placeholder。
- `ReaderView.swift:694-701`：`readerPageRevisionKey` 只有 layout/theme/customFont/night；`readerLayoutKey:704-724` 不含 viewport、safe area、章节内容。
- `ReaderView.swift:2866-2876`：富文本缓存键 = 上述身份 + 语音位置 + revision。
- `ReaderView.swift:6716-6726`：同 signature/key 直接返回已有 attributed string；`ReaderPageTextView.swift:198-205` 又按同一个 key 决定是否给 UITextView 重新赋值。
- 几何变化却会重分页：`ReaderView.swift:757-775,1264-1270,6480-6518`。该路径不会清空 pageTextCache。

**触发路径 / Inferred**

显示并预热某章第一页 → 旋转、分屏或容器安全区变化 → 同一章第一页仍 ordinal=0/firstParagraph=0，但容纳字符数改变 → 新页模型取到旧富文本。即使页面 controller 被重建，`pageAttributedText` 仍命中旧值。后续页面有的命中旧分片、有的使用新分片，可能重复/漏读；高度缩小时旧分片又被 `pageSurface:3067-3075` 裁切。类似问题也发生在首段不变的正文刷新。

**验证**：独立模型 `pagination-model-check.py` 的 `geometry-repagination-stale-render-key` 已执行，证明 key 不区分不同分片；示例 ABCD→ABCDEF 是模型分片，不是伪称 TextKit 测量结果。实际 UIKit 重分页回归 NOT RUN。

**修复方向**：区分“定位身份”与“渲染版本”；渲染版本至少绑定章节内容 revision + pagination layout revision/实际文本分片范围，传递给富文本缓存、UIView 更新和 hosting-controller 内容更新。不能只加全窗口 revision，否则邻章预取仍会无谓重建所有页面。

## 2. P1 — 中间段落更新被章节缓存吞掉

**Observed**

- `ReaderView.swift:778-780`：`chapterPageContentSignature` 仅标题、段落数量、首段 hash、尾段 hash。
- `ReaderView.swift:6480-6511`：上述 signature 相同就复用旧 `[ReaderPageBlock]`。
- 外层虽有全量 fingerprint (`3034-3043`)，且 `.onChange(content):1170-1197` 专门声称处理“middle paragraph”，但 `resetWindow:1734-1762` 未清 chapterPageCache；重建仍命中弱 signature。
- window signature `669-673` 也只摘要首尾。

**触发路径 / Inferred**：章节 `[首,旧中,尾]` 更新成 `[首,新中,尾]`，标题、段数不变 → 外层重建了，内层继续复用旧正文。若更换来源后章号/标题/首尾相同，也有同类风险。

**验证**：`middle-edit-cache-collision` 已执行，属于确定性等值碰撞，不依赖 Swift hash 随机化或碰撞概率。

**修复方向**：章节内容建立单一、完整且显式的 revision（原始内容哈希/数据层修订号）；窗口缓存、分页缓存、富文本缓存共用。异步结果合入前比对同一 revision。

## 3. P1/P2 — 118 把冷缓存窗口都变成同步分页，预热未隔离主线程成本

**Observed**

- `ReaderView.swift:6493-6518`：`synchronousRadius = windowRadius`；只有 `abs(chapter-current) > synchronousRadius` 才允许占位，窗口内所有 cache miss 都执行 `appendPages`。
- `appendPages:6567-6599` 同步进入 `ReaderChapterPaginator.paginate`；每个段落走 TextKit (`ReaderChapterPaginator:143` → `ReaderPageLayoutEngine:235-260`)。
- 本地窗口至少左右各五章（`ReaderView:490-496`），一次冷启动/布局失效可同步测 11 章。
- `rebuildPagedBlocksCache:6245-6248` 同步构建；`schedulePagedBlocksCacheRebuild:6336-6344` 明确在 MainActor；后台 warmup 同时可能重复测量相同章。
- Git 118 diff：网络书原先半径为 settled ? 3 : 1，现扩大为整个 windowRadius；本地全窗口同步策略在 118 之前已经存在，并非全由 118 引入。

**Inferred**：长章节、首开、调整字体/旋转后会出现主线程卡顿；后台预热的存在不等于主线程没有分页。源码足以证明同步执行路径，但未测设备耗时，不能报具体帧率或卡顿时长。

**验证**：`synchronous-radius-equals-window` 已执行：半径 5 的 11 章里，符合延后条件的数量为 0。

**修复方向**：当前可见页/必要邻页有限同步保障，其余明确交给队列；in-flight job 按内容+布局去重；按实测主线程毫秒预算验收，而非继续扩大预热范围。

## 4. P2 — 段距小于行距时，测量/渲染契约仍不一致

**Observed**

- UI 允许段距 0...28、行距 0...18，互不约束（`ReaderView:4456,4462`）。
- 分页器在段落间只加 `typography.paragraphSpacing`（`ReaderChapterPaginator:145-153,183-201`）。
- 富文本 builder 设置 lineSpacing=L，paragraphSpacing=max(0,P-L)（`ReaderPageTextView:49-61`）；仓库测试也把 L + (P-L) = P 作为其依据（`ReaderPageTextBuilderTests:55-57`）。
- 这个补偿公式只在 P>=L 成立；P<L 时按该仓库契约实际间距至少 L，分页仍按 P 预算。16pt 固定 buffer 不能兜住多段累计差值。

**Inferred**：如行距18/段距0的许多短段，可再次发生底部截字。需真机验证 TextKit 各系统版本的段尾 lineSpacing 行为；这里不把公式推导冒充 UIKit 测量。

**验证**：`spacing-contract-with-paragraph-less-than-line` 模型执行，10 个间隔累计差 180pt；结果标 `MODEL_ONLY`。

**测试缺口**：现有 overflow fixture 只有 L=6/P=10；builder fixture L=8/P=10；均未覆盖 P<L、P=0、混合字体/emoji/空行。应直接用最终 attributed string 测得的 line fragments 切页/验证，避免两套间距公式。

## 5. P2 — 含图页面退回另一套渲染器，图片预算也未传到实际视图

**Observed**

- 只要页面含一张图，全部正文转入 `legacyTextStack`（`ReaderView:2822-2826,2840-2860`），其正文用 SwiftUI Text（`3251-3277`），而分页依然按带 CJK compression/justified 的 TextKit 测（`ReaderPageLayoutEngine:217-233`）。
- 插图预算使用 `min(policyMaximum, typography.contentHeight-captionBudget)`（`ReaderChapterPaginator:86-96`）；实际 `illustrationCard` 只传 policyMaximum（`ReaderView:3291-3296`），漏传正文上限。
- `ReaderImageSizingPolicy.maximumHeight:108-110` 用 viewport/pagePadding/footerHeight 的旧估算，不使用 geometry safeTop/safeBottom/bodyTop/bodyBottom。
- inline 模式正文首图时，`currentIncludesTitle=true` 但 entries 为空；非 single 图片溢出判断要求 `!currentEntries.isEmpty`（`ReaderChapterPaginator:109-119`），因此标题+首图超预算不会先 flush。
- 含图正文语音高亮额外上下各6pt（`ReaderView:3270`），分页没有这12pt。

**Inferred**：小容器、大安全区、inline 大标题+高图、混排+朗读时有溢出风险；图像下载后实际尺寸变化还可能使用户看到位置跳变。不是声称每个正常竖屏图片都溢出。

**修复方向**：图文都产出统一布局块/实际高度预算；视图消费 paginator 给出的约束，不重算另一套最大高度；混排正文仍使用同一 TextKit 属性与测量链。

## 6. P2 — 阅读位置只有段号/页序号，重排无法保证同一字符位置

**Observed**

- `ReaderChapterPosition` 没有段内字符偏移和 layout revision（`ReaderChapterWindow:57-68`）。
- `ReaderPageRestoration.index:60-67` 即使布局已改变，仍把同 ordinal/firstParagraph 当精确命中；fallback `pageContaining:107-117` 则选择同段最后一个 continuation。
- `ReaderPositionMapping.page(containingParagraph):53-69` 又选择同段第一个 continuation；切模式入口 `ReaderView:1206-1230` 走后者。

**Inferred**：一个长段跨多页时，旋转/字号变化/模式切换会向前重读或向后漏读。邻章插入保持旧页序号是合理的，但“邻章插入”和“本章重排”不能使用同一种精确匹配判据。

**修复方向**：锚点以 chapter ID + paragraph ID + UTF-16/character offset 表示；旧 ordinal 只在同 layout revision 内作快速路径。段级书签可另保留当前语义。

## 7. 次要但确定的几何边界

`ReaderPageGeometry:151-160` 先以 footer 计算 bodyBottom，再把 contentHeight 强制扩到至少120。小窗口（例如200高/safeTop59/safeBottom34）实际 body end=213，footer top=152。模型 `minimum-body-height-overlaps-footer` 已执行。这不证明正常 iPhone 竖屏有问题，但“永不越过页脚”的注释与实现不一致，横屏小窗/瞬态布局应覆盖。

## 117 / 118 实际修了什么

|版本|Observed 改动|不能由此证明|
|---|---|---|
|117 `771d2e4`|去掉分页/切片阈值的0.5pt容差；相关 ReaderView 变化要结合 whitespace-normalized diff 阅读|没有消除测量/渲染两套文档；不能证明所有截断已解决|
|118 `bffedba`|footer safeBottom 从一半改全量；底部 inset12→14，body/footer gap4→10；分页 buffer8→16；网络书允许 warmup；同步半径扩大|不能修复旧富文本命中；更大的留白不是正文完整性证明；不能凭提交标题“zero-stutter”认定无卡顿|
|HEAD `5686485`|调整 geometry 测试断言匹配新 safeBottom 计算|只是测试预期同步，不是端到端翻页验收|

## 已有保护：不要误报成“所有异步结果都无保护”

- warmup 在 await 前后校验 Task cancellation、windowGeneration、paginationWarmupGeneration、layout signature（`ReaderView:1934-1947,1992-1994`），旧代/旧布局通常会被拒绝。
- `ReaderPageTextCache` 有 NSLock 与 signature 二次校验（`6744-6761`）；主要缺陷是 signature 语义不足，不是完全没有锁。
- 手势期间 `schedulePagedBlocksCacheRebuild` 延后（`6324-6344`），再由 interaction gate 处理。需要控制器层端到端竞态测试，不能只看这几行就宣称整个系统安全或不安全。
- 章节预热合并 `1996-2001` 没有再比较 live content revision，但旧 snapshot 带自己的 contentSignature；一般不同首尾会在消费时拒绝。中段变更之所以危险，核心仍是问题2的弱 signature。

## 验收矩阵与测试缺口

1. **正文守恒**：每个章节转显示文本后，按 paragraph+chunk source range 拼回原文；每字符恰好显示一次；不能只查最后一句 contains。
2. **渲染守恒**：最终 attributed text 的 glyph 可见区不越 bodyRect；包含 font/行距/段距/缩进/中英混排/emoji/标点/图片/inline标题矩阵。
3. **缓存正确性**：冷/热缓存产物完全相同；中段刷新；旋转后第一页 identity 相同但 text 改变；同 book/source revision；旧 prewarm 延迟返回。
4. **位置正确性**：长段阅读到中间字符，改字号、横竖屏、三种翻页互切、滚动互切、前方插入章节后仍定位同一字符。
5. **性能**：11章冷缓存/单章10万字/连续前后翻；用 signpost 统计 MainActor layout 工作、首帧耗时、p95帧耗时、重复分页 job 数；不能仅检查 warmup 常量大小。
6. **现有 tests 限制**：`ReaderPagedOverflowTests:65-94` 容许+1.5pt，且只用离屏 NSLayoutManager；`121-153` 欢迎书只检查末句存在+单一717pt预算，不连真实 geometry/cache/UITextView/controller。`ReaderPageSelectionTests` 验证身份在数组重排不变，没有验证文本内容改变后的 invalidation。检索未发现 `ReaderPageTextCache`/chapter contentSignature 的直接回归测试。

## 已执行产物

- `pagination-model-check.py`：5项独立 Python 逻辑检查，4项可确定重现；spacing项为契约模型而非 UIKit 测试。
- `pagination-model-results.json`：实际输出。
- `graph-pagination.json`：本审查的语义图谱分片，每条边含 evidence confidence。

推荐下一轮先落缓存版本和字符锚点契约+失败测试，再统一布局渲染；不要同时继续加 buffer、扩大缓存半径、叠控制器补丁。尚未实施这些修复。
