# 阅读模式：卡顿与跳页的修复对账（1.0.78）

本文只记录**已经落地在代码里的东西**和**实测能证明的因果关系**，不写“应该会好”。
凡是没在真机上跑过的判断，都标成推断。

## 1. 「翻页跳回前面一页」

| 项 | 值 |
|---|---|
| 症状 | 在第五章翻页，画面回到第二章的页 |
| 根因 | 页游标存的是**数组下标**；预取上一章后整个 `pagedBlocks` 前移，同一个下标指向了别的页 |
| 修复 | `01ec90b`：`ReaderPageIdentity` 页身份 + `pageIdentityTracker` + `ReaderPageRestoration` |
| 代码位置 | `ReaderView.swift` `currentPageAnchor()` / `restoredPageIndex(_:in:)`；`ReaderPageSelection.swift` |
| 追加保护 | `schedulePagedBlocksCacheRebuild()` 在手势期间只置 `rebuildDeferred`，等 `handlePageInteraction(false)` 再重建 |
| 状态 | 已修复（代码层）；单测 `ReaderPageSelectionTests` 覆盖锚点恢复 |

## 2. 「左右滑动卡一下 / 翻页模式掉帧」

这一条之前只做过**判定口径**和**手势期禁重建**，没有动真正的开销来源。

### 2.1 开销来源（Observed，代码可数）

`ReaderView.appendPages` 对每个正文段落调用：

1. `ReaderPageLayoutEngine.measureHeight(display)` → 建一套 `NSTextStorage + NSLayoutManager + NSTextContainer`；
2. 段落超出当前页时再调 `split()` → 同一段文本**再建一套**重新排版；
3. `split()` 内部对每个切片调 `measureHeight(chunk)` → 每个切片**再各建一套**。

一个落到 3 页的段落 = 5 次 TextKit 全排版；一章 3000 字、十几个长段落 = 几十次。
这些全部发生在 `@MainActor`（`pageLayoutTask = Task { @MainActor in ... rebuildPagedBlocksCache() }`），
也就是直接压在章节切换的那一帧上。

### 2.2 本轮改动（1.0.78）

- `ReaderPageLayoutEngine.metrics(for:typography:)` 暴露单次排版的行度量；
- 新增 `split(_:metrics:firstPageHeight:fullPageHeight:typography:)`，切片高度由行度量**算术推导**：
  切片未到段尾时扣一次 `lineSpacing`（`lineMetrics` 已对段尾行不加间距）；
- `appendPages` 改为「测量一次 → 用同一份度量切页」，每段从 2~5 次 TextKit 排版降到 **1 次**。

### 2.3 验证

- `testMetricsTotalMatchesMeasureHeight`：度量总高 ≡ 整段测量；
- `testSplitWithPrecomputedMetricsMatchesMeasuredHeights`：切片文本完全一致、切片高度与单独测量误差 ≤0.5pt、拼回原文无丢字；
- `testEveryChunkFitsItsPageBudget`（既有）继续锁住「每片不超预算」。

## 3. 还没解决的（不要当成已完成）

| 问题 | 现状 | 下一步 |
|---|---|---|
| 新章节首次分页仍在主线程 | 未被搬走，只是变便宜了 | 需要把 `appendPages` 的输入抽成值类型快照，在后台算完再回主线程发布 |
| 120Hz 体感 | `CADisableMinimumFrameDurationOnPhone=true` 已在 Info.plist；`UIPageViewController` 实际帧率**未实测** | 真机用 `ReaderFrameRateSampler` 读数字，不再靠体感 |
| 仿真翻页 | `UIPageViewController(.pageCurl)` 由系统驱动，开销不受本项目控制 | 若实测长期低于 60fps，改用自绘 curl |

## 4. 结论

「1、2 你前面不是改过了吗」——改过的是**正确性**（第 1 条）和**判定口径**（第 2 条）；
真正的掉帧来自分页重复排版，这一轮才动。1.0.78 之后如果还卡，剩下的只能是主线程分页本身，
那就必须做后台分页，而不是继续调参数。
