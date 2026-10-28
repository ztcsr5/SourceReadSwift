# 1.0.82 — 阅读帧率审计与两处真实开销

## 先回答“1、2 不是改过了吗”

改过的是**一部分**，不是全部。逐版本对照：

| 用户报告 | 之前动过什么 | 实际覆盖范围 | 1.0.82 状态 |
|---|---|---|---|
| 视频 2：第 5 章翻页跳回第 2 章 | 1.0.66 页身份 key；1.0.81 `adopt(visible:)` | 页游标不再用数组下标恢复；预取前插不再把 binding 写回旧槽位 | 已修（1.0.81） |
| 视频 1：左右滑动起手卡一下 | 1.0.66 `ReaderInteractionGate`、hosting LRU(8)、prewarm(+1/-1/+2) | 只减少了“手势中新建页面”的次数；没有消除每次 SwiftUI 更新对 UIKit 树的递归遍历 | 1.0.82 去掉每次 update 的递归遍历，仍待真机确认 |
| 第 2 点：其他翻页模式掉帧、不是 120Hz | 1.0.50 加了 `ReaderFrameRateSampler`；1.0.66 给封面做了 ImageIO 降采样 | 采样器只是仪表；降采样只治主页封面解码，不改变渲染通道的帧率上限 | 1.0.82 去掉覆盖模式每帧的全屏 shadow；滚动/仿真仍是 60Hz 通道 |
| 主页“假 120Hz” | 1.0.66 封面降采样 | 只覆盖封面解码，不覆盖滚动时的阴影/布局 | 未完成，待逐屏采样 |

结论：1.0.66 的交接文字把“采样 + 局部优化”写成了“帧率修复”，这是过度表述。
1.0.82 起按渲染通道分别记账，不再把采样当成修复。

## 三个翻页通道的真实上限

| 模式 | 实现 | 帧率上限来源 |
|---|---|---|
| 滑动（scroll） | `WebScrollReaderView` → `WKWebView`（`ReaderView.swift` 的 `scrollReaderContent`） | WebKit 的 UI 进程渲染与滚动节奏；ProMotion 下实际按 60Hz 出帧，`CADisableMinimumFrameDurationOnPhone` 只解锁本 App 的 CA，不解锁 WebKit |
| 平移（pageTurn） | `UIPageViewController(transitionStyle: .scroll)` | 原生 UIScrollView，可 120Hz；卡顿来自手势中按需构建 `UIHostingController` 与每次 update 的树遍历 |
| 覆盖（cover） | SwiftUI `DragGesture` + 每帧改 `coverDragTranslation` | SwiftUI 逐帧重算 + 全屏 `.shadow` 离屏模糊；1.0.82 已去掉 shadow |
| 仿真（pageCurl） | `UIPageViewController(transitionStyle: .pageCurl)` | Apple 的 CA 卷页过渡，按 60Hz 设计，无法用应用层参数提到 120Hz |

## 1.0.82 的两处改动

### 1. 去掉 `updateUIViewController` 里的递归 UIKit 遍历

`PageCurlReaderView.updateUIViewController` 原来每次 SwiftUI 刷新都调用：

- `suppressInternalTapGestures(on:)`：遍历 `gestureRecognizers`；
- `normalizeInternalScrollViews(in:)`：递归整棵子视图树。

阅读器在滚动/翻页时会频繁更新页码、进度、chrome 状态，于是这两个遍历在每一帧都可能跑一次。
现在只在 `makeUIViewController`（含一次 `DispatchQueue.main.async` 兜底）和
`didFinishAnimating` 之后执行；内部 `UIScrollView` 是随 page controller 创建的，
`contentInsetAdjustmentBehavior = .never` 会一直保留。

### 2. 覆盖模式用渐变代替全屏 shadow

覆盖模式的下一页/上一页是整屏尺寸，`.shadow(radius: 10)` 会在每个拖拽帧做一次离屏模糊。
改为 24pt 的 `LinearGradient` 边缘条：视觉上仍是书页投影，渲染成本从 blur 降为普通填充。

## 没有解决的问题（明确记账）

1. **滑动模式仍然是 WKWebView**，所以“滑动不是 120Hz”是架构事实，不是参数问题。
   要真正 120Hz 必须回到 TextKit 1（`NativeReaderTextView`），并补上章节标题的独立样式、
   增量追加与锚点保持；这是 1.0.83 的主线，不再用 WebView 打补丁。
2. **仿真卷页仍是 60Hz**。`UIPageViewController.pageCurl` 是系统过渡；要么接受 60Hz，
   要么自研卷页渲染（OpenGL/Metal 或 CALayer 变换）。在自研完成前不承诺 120Hz。
3. **主页/发现页**还没有逐屏帧时间数据。1.0.82 不猜改动，下一步用
   `ReaderFrameRateSampler` 同级的 `CADisplayLink` 给主页加采样，再按数据改。

## 验证

- 编译与单测：GitHub Actions iOS workflow（1.0.82 推送后记录 run id）。
- 真机：设置 → 阅读器性能（诊断）里的帧率/掉帧数，分别记录滑动、平移、覆盖、仿真四种模式。
- 复核点：覆盖模式拖动时不再出现整屏模糊；平移模式第一次滑动不再有可感知的起手停顿。
