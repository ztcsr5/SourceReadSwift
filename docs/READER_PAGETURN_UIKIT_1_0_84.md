# 1.0.84 — 平移翻页并入 UIKit 分页容器

## 背景

1.0.83 只把「覆盖」从 SwiftUI 手势换成 `UIScrollView(isPagingEnabled)`。用户在真机上报告的两个现象仍然存在：

1. 左右滑动会卡顿；翻页偶尔跳回前面的章节；
2. 滑动以外的翻页模式丢帧，明显不到 120Hz。

原因不是 1.0.83 没生效，而是它只覆盖了 `.cover`：

| 模式 | 1.0.83 实现 | 每帧主线程工作 |
|---|---|---|
| 覆盖 `.cover` | `CoverPageReaderView` 三槽位 `UIScrollView` | 无 SwiftUI body 求值 |
| 平移 `.pageTurn` | `UIPageViewController(.scroll)` | 手势里构建 `UIHostingController` |
| 仿真 `.pageCurl` | `UIPageViewController(.pageCurl)` | 同上，且卷页是系统 60Hz 转场 |
| 滑动 `.scroll` | `WKWebView` | WebKit 合成通道 |

## 本版改动

`.pageTurn` 与 `.cover` 共用 `CoverPageReaderView`：

- 三个槽位在 `viewDidLoad` 建好后只换 `rootView`，翻页不再新建 hosting controller；
- 手势与减速由 `UIScrollView` 自己的 `UIPanGestureRecognizer` 驱动，拖拽帧不经过 SwiftUI；
- `commitCoverTurn` 继续在提交后按 `ReaderPageRestoration` 锚点复算，保留 1.0.81 的跳章修复。

配套：`CoverPageHostController` 新增 `onPageContainerLayout`。平移模式的页面在 `UIHostingController` 里，`PreferenceKey` 回不到根视图；不补这条回调，分页会按根视口排版，页尾会被裁掉一行。回调做了 0.5pt 去重并延迟一个 runloop，避免 "modifying state during view update"。

## 明确未改

- `.pageCurl` 仍走 `UIPageViewController(.pageCurl)`。iOS 的卷页转场由系统实现，按 60Hz 设计，应用层无法把它提到 120Hz；
- `.scroll` 仍是 `WKWebView`。它的滚动是原生合成，但文本排版在 WebKit 里，长章节的布局和选区开销与 TextKit 不同；
- 覆盖与平移目前的视觉差异只在页面切换手感，真正的"上一页压住下一页"叠层尚未实现。

## 验证

- iOS run `40642380485`：Build success / Test success；
- 新增行为由既有 `ReaderCoverSettlePolicyTests` 覆盖（过半提交、短拖回弹、首尾边界、零宽）；
- 版本 `1.0.84 (Build 85)`，Info.plist 与 project.yml 同步。
