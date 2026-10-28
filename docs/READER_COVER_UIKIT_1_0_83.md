# 1.0.83 — 覆盖模式改为 UIScrollView（真正吃到 120Hz）

## 问题

读者视频里三个翻页模式掉帧，覆盖模式最明显；滑动模式相对流畅。1.0.82 已经去掉了
覆盖模式每帧的全屏 `.shadow`，但掉帧没有消失。

原因不在阴影，而在渲染通道：

```
coverPagedReaderContent
  GeometryReader
    ZStack
      readerPage(for: pagedBlocks[safeIndex])       // 每帧重新求值
      readerPage(for: pagedBlocks[safeIndex + 1])
      readerPage(for: pagedBlocks[safeIndex - 1])
    .gesture(DragGesture.onChanged { coverDragTranslation = ... })
```

`coverDragTranslation` 是 `@State`。手指每移动一个事件，SwiftUI 就把整个
`GeometryReader` 子树重新求值一次：三页 `readerPage`、三次 `ReaderPageIdentity`、
三次 `.clipped()` / `.overlay()` diff。UIKit 的 pan 是 120Hz 事件，SwiftUI 的
body 求值跟不上，于是实际出帧被压在 60Hz 附近，还带抖动。

这不是「参数没调好」，是通道选错了。

## 改动

新增 `CoverPageReaderView.swift`（`UIViewControllerRepresentable`）：

- 内部是 `UIScrollView(isPagingEnabled = true)`，三个 `UIHostingController` 槽位
  （上一页 / 当前页 / 下一页），当前页固定在 `contentOffset.x == width`；
- 拖拽完全由 UIKit / Core Animation 驱动，**拖拽期间不触发任何 SwiftUI body**；
- 只有 `pageIdentity` 或 `contentRevision` 变化时才替换三个 rootView；
- 松手后由 `ReaderCoverSettlePolicy` 判定：过 0.5 页提交，否则回弹；
- 提交时 `onCommit(±1)`，阅读器更新页游标，`pageIdentity` 变化后控制器无动画回中，
  用户手指下的那一页仍然是同一页。

`ReaderView.coverPagedReaderContent` 由 197 行缩到 90 行；`finishCoverGesture` 和
两个 `@State`（`coverDragTranslation`、`coverIsAnimating`）删除。

1.0.81 的页身份修复保留：`commitCoverTurn` 提交后仍用
`ReaderPageRestoration.index(anchor:in:fallbackIndex:)` 复算一次，预取前插不会把
第五章送回第二章。

## 边界

| 场景 | 行为 |
|---|---|
| 第一章继续往右拖 | `hasPrevious == false` → 回弹，不提交 |
| 最后一章继续往左拖 | `hasNext == false` → 回弹 |
| 邻章还在下载 | 提交后 450ms 兜底回中，不会停在边缘空白页 |
| 拖拽中来内容更新 | `apply` 只换 rootView，不动 offset |
| 旋转 / 分屏改宽度 | `viewDidLayoutSubviews` 重排三页并回中 |

## 测试

`ReaderCoverSettlePolicyTests`：过半提交、短拖回弹、首尾边界回弹、零宽度不除零。

## 仍然存在的上限（如实记账）

| 模式 | 通道 | 上限 |
|---|---|---|
| 滑动 | WKWebView | WebKit 合成节奏，本轮未动 |
| 平移 | UIPageViewController(.scroll) | 原生可 120Hz，卡顿来自按需构建页面 |
| 覆盖 | UIScrollView（本轮） | 原生可 120Hz，待真机确认 |
| 仿真 | UIPageViewController(.pageCurl) | Apple CA 卷页按 60Hz 设计，应用层无法提高 |

覆盖模式改完后，剩下的是「平移模式手势中构建 hosting controller」和「滑动模式的
WebKit 上限」。这两项分开处理，不再混在一个「帧率修复」里。
