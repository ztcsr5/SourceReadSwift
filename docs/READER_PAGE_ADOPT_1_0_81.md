# 1.0.81 — 翻页回跳的第二个根因（window 前插 + binding 过期）

## 现象

三种分页模式（平移/覆盖/仿真）在读第五章时，翻页会整页跳回前面的章节（报告中是第二章）。
1.0.66 的 `01ec90b` 修过一次：页游标从「数组序号」改为「页身份 key」，并在手势期间禁止重建。
1.0.79 仍能复现，说明还有第二条路径。

## 根因

`PageCurlReaderView.sync()` 每次 SwiftUI 刷新都会把「屏幕上的页」和
`pagedPageIndex`（SwiftUI binding）对齐。窗口为了连续阅读会预取上一章：

1. 读者在第 5 章第 3 页，`pagedPageIndex = 12`（窗口里第 4 章占 9 页）。
2. 第 4 章加载完成，`buildReaderPageBlocks()` 把 9 页插到数组前面。
3. 屏幕上的页没变，但它的 index 从 12 变成 21。
4. `sync()` 用页身份 key 找到了 `displayedIndex = 21`，但
   `ReaderPageCurlSyncPolicy` 仍按「displayed != desired → move(desired)」处理，
   而 `desired` 还是过期的 12。
5. `setViewControllers` 把读者送回 index 12 —— 也就是第 4 章/更前面一页。

1.0.66 修的是「index 用于恢复」的路径；这条是「index 用于纠正 binding」的路径，
两者独立。

## 修复

`ReaderPageCurlSyncPolicy` 增加 `.adopt(visible:)`：

- 记录 `lastDesiredIndex`（上一次 sync 时 binding 的值）。
- 若 `displayedIndex != desiredIndex` 且 `desiredIndex == lastDesiredIndex`，
  说明 SwiftUI 没有提出新的翻页要求，只是数组位移了 → 采纳屏幕页。
- 若 `desiredIndex != lastDesiredIndex`（目录跳转、TTS、模式切换），
  仍然 `move(to: desired)`。
- `contentRevisionChanged`（重排版/换字体）优先级最高，保持 `reloadCurrentPage`。

`Coordinator.adoptVisibleIndex` 把可见 index 延迟写回 binding，并加了两道 guard：
数组仍包含该页、binding 仍是旧值（同帧内的显式跳转不会被吞掉）。

## 覆盖

- `ReaderPagedNavigationPolicyTests.testPageCurlSyncAdoptsVisiblePageWhenWindowShifts`
  - 前插位移 → `.adopt(visible: 21)`
  - 显式跳转 → `.move(to: 5)`
  - 首次同步（无历史）→ 旧行为 `.move(to: 12)`
  - 重排版 → `.reloadCurrentPage`

## 版本

1.0.81 (Build 82)。1.0.80 的 TOC 审计修复全部包含在内；1.0.80 的 CI 产物被
1.0.81 的推送按 concurrency 规则取消，未发布，也不影响代码。
