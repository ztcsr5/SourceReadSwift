# 纸间 · 阅读器覆盖层重构（B 方案）交付与审查报告

生成时间：2026-11-10 21:40 (+08:00)
分支：`codex/perf-120hz-1109`
当前 HEAD：`4cf5304f`
可安装包：`SourceReadSwift-1.1.8-build138-4cf5304-unsigned.ipa`（SHA-256 `7068CEB1E740869E88AEFF133F5B1F4C8A3898A529A49746993090012D90DA1C`，24,797,145 B）

---

## 0. 一句话结论

阅读器从 `NavigationStack` 的 destination 改成了根视图之上的覆盖层，进入/退出改由自绘的进度驱动过渡。**编译与打包通过，全量测试 11 项失败**：其中 4 项是本次刻意更改的契约（旧断言待更新），7 项是这次重构引入的 UI 回归（待修）。真机效果未验证。

---

## 1. 为什么要改：根因（有实测证据，非推断）

### 1.1 症状

| 编号 | 现象 |
|---|---|
| 3 | 正文页轻碰左缘，阅读菜单闪一下，且不退出；疑似两套侧滑 |
| 4 | 从阅读返回主页，底部导航栏要等一会才出现 |
| 6 | 从详情/阅读快速侧滑回主页，主页要"加载" |

### 1.2 定位过程

1. **读代码枚举**：全仓库 `.toolbar(..., for: .navigationBar/.tabBar)` 仅 10 处，UIKit 侧 `setNavigationBarHidden` / `setTabBarHidden` **0 处**。因此只有一个变量：「谁在什么时刻把可见性按下去」。
2. **内置日志实证**（`NavigationTrace`，App 内 20Hz 采样 UIKit 状态）：
   ```
   +  4.122s  pop    willDisappear interactive=true isPop=true
   +  4.122s  chrome release ... owners=0 hidden=false
   +  4.215s  STALL  主线程停顿 61 ms
   +  4.227s  chrome acquire ... owners=1
   +  4.228s  pop    结束 cancelled=true
   ```
   一次没滑够距离的侧滑，在 pop 起点把 tab bar 放出来，100ms 内又藏回去 → 肉眼即"闪一下"。同一序列在一次手势里重复 4 次。
3. **另一个关键事实**：`shelf projection REBUILT 0.0ms` —— 投影计算本身是 0ms，之前怀疑的"延时 120ms 重算书架"**被证伪**。
4. **视频逐帧对比**（参考 App vs 我们）：
   - 参考 App：`2.67s 正文 → 3.00s 正文+tab bar 半透明淡入 → 3.33s 主页`，栏**跟着转场淡入**。
   - 我们：一滑就整条弹出，是**瞬切**，说明 chrome 被状态直接改写，不走 UIKit 转场。

### 1.3 结论

`BookshelfReaderGatewayView` 是 `navigationDestination` 的 destination。手势一开始，SwiftUI 就拆掉它：

- destination 上的 `.toolbar(.hidden, for: .navigationBar/.tabBar)` 随视图销毁而消失 → 主页的 `.automatic` 立刻生效 → **导航栏与右上角按钮瞬切弹出**（"当作已经回到主页"）
- `gateway.onDisappear` 触发 `releaseTabChromeHidden` → **tab bar 瞬切** → 手势取消后 `acquire` → 闪
- 主页 `onAppear` 跑投影刷新 → **书架重建**（"主页加载"）

补丁打不完的原因：这不是参数问题，是**pop 路径本身**同时承载了 chrome 恢复、状态重建、手势竞争三件事。

---

## 2. 架构决策：B 方案

```
RootTabView
└─ ZStack
   ├─ navigationContent      ← 主页/寻书/设置/搜索，全程不销毁
   └─ ReaderOverlayLayer     ← AppState.readerOverlay 驱动
```

主页永不离场，因此不存在"恢复 chrome"这个动作；退出由自绘手势驱动，不存在 UIKit pop 与 SwiftUI `isPresented` 抢跑。

### 取舍

| 项 | 结论 |
|---|---|
| iOS 原生 `navigationTransition(.zoom)` | **放弃**。它只对 NavigationStack push 生效，与覆盖层不兼容。改用自绘进度驱动过渡，视觉等价。 |
| 其它页面路由 | **保留**。详情、书架、寻书的业务路由未动，只把"进入阅读器"这一跳改为抬覆盖层。 |

---

## 3. 改动清单

### 3.1 新增文件

| 文件 | 行数 | 作用 |
|---|---|---|
| `Features/Reader/ReaderOverlayLayer.swift` | 117 | 覆盖层视图 + `ReaderOverlayRequest` 定义 |
| `Features/Reader/ReaderTransition.swift` | 98 | `ReaderTransitionPolicy`（纯函数策略）+ `ReaderTransition`（进度协调器） |
| `SourceReadSwiftTests/ReaderTransitionPolicyTests.swift` | 65 | 策略单测，5 个用例 |

### 3.2 修改文件

| 文件 | 改动 |
|---|---|
| `App/AppState.swift` | 新增 `@Published var readerOverlay: ReaderOverlayRequest?` |
| `App/RootTabView.swift` | `body` 改用 `ZStack { navigationContent; if let request = appState.readerOverlay { ReaderOverlayLayer(...) } }`；新增 `.animation(.easeInOut(0.28), value: appState.readerOverlay?.id)` |
| `Features/Bookshelf/BookshelfView.swift` | `ContextualBookRoute` 删除 `.read` 分支；`readingDeskEntry` 改为设置 `appState.readerOverlay`；`navigationDestination` 只剩 `.detail` |
| `Features/Discover/BookDetailView.swift` | `openReadingRoute`：本地书直接抬覆盖层并 `return`，非本地书保留原 `readingRoute` |
| `Features/Search/GlobalSearchView.swift` | `resultLink`：书签结果直接抬覆盖层，其余走原 `selectedEntry` |
| `Features/Settings/SettingsView.swift` | 3 处 `NavigationLink { BookshelfReaderGatewayView }` → `Button { appState.readerOverlay = ... }`（阅读历史 / 阅读最多 / 最近阅读） |
| `Features/Reader/ReaderExitSwipeBridge.swift` | 新增 `onChanged: (CGFloat) -> Void`、`onEnded: (CGFloat, CGFloat) -> Void`；`handlePan` 在 `.changed` 上报实时位移，`.ended/.cancelled/.failed` 上报原始 translation/velocity；保留既有 `onExit` 供 ReaderView 使用 |
| `Features/Bookshelf/ReaderOpeningPage.swift` | `ReaderOpeningPresentation` 不再渲染 `ReaderOpeningStatus` 占位页与 0.18s 淡出（此前造成文字重影），只保留到达探针与 ready 信号 |

### 3.3 新增 API

```swift
struct ReaderOverlayRequest: Identifiable {
    let book: BookshelfBook
    var initialBookmark: ReaderBookmark?
    var initialChapterIndex: Int?
    var coverRect: CGRect?      // 预留：拿到真实封面位置时用
    var coverImage: UIImage?
    var id: String { ... }
}

enum ReaderTransitionPolicy {
    static func dismissalProgress(translation: CGFloat, width: CGFloat) -> CGFloat
    static func shouldDismiss(translation: CGFloat, velocity: CGFloat, width: CGFloat) -> Bool
    static func targetRect(cover: CGRect, screen: CGSize, progress: CGFloat) -> CGRect
    static func cornerRadius(progress: CGFloat, compact: CGFloat, full: CGFloat) -> CGFloat
    static func contentOpacity(progress: CGFloat) -> Double
    static func coverOpacity(progress: CGFloat) -> Double
}

@MainActor final class ReaderTransition: ObservableObject {
    var progress: CGFloat        // 0 = 贴在封面位置，1 = 全屏
    var reducesMotion: Bool
    func open()
    func drag(translation: CGFloat, width: CGFloat)
    func endDrag(finish: Bool, onFinish: @escaping () -> Void)
}
```

---

## 4. 过渡行为规格

进度 `p` ∈ [0, 1]，`0` = 完全退回封面位置，`1` = 全屏。

| 属性 | 映射 |
|---|---|
| 位置/尺寸 | 封面矩形 → 全屏矩形，线性插值（`targetRect`） |
| 缩放 | `rect.width/screen.width`、`rect.height/screen.height`，作用于**已按最终尺寸排版**的内容 |
| 圆角 | `12 → 0` |
| 阴影 | `opacity 0.22·(1-p)`，`radius 24·(1-p)` |
| 封面可见度 | `1 → 0`，`p ≥ 0.72` 时为 0 |
| 正文可见度 | `p ≤ 0.62` 时为 0，之后线性升到 1 |

**跟手**：拖动中 `p = 1 - dx/width`，逐帧写入，无动画。
**松手**：`velocity > 820` 完成；`velocity < -820` 取消；否则 `translation > max(96, 0.32·width)` 完成。
**取消**：`p` 弹簧回 1。
**完成**：`p → 0`，延迟 0.20s（减少动效时 0）再移除覆盖层，避免中途闪主页。

缩放不改变布局尺寸，因此 WebView 不会因动画反复重排（对应要求 6）。

---

## 5. 测试现状

### 5.1 通过

- 编译：`#725` package job **success**
- 新增 `ReaderTransitionPolicyTests` 5 用例
- 单测 1931 项中 1925 通过

### 5.2 失败（共 11）

**A 类：本次刻意更改的契约，旧断言待更新（4 项）**

| 测试 | 原因 |
|---|---|
| `ReaderTabChromeExitTests.testRealUIKitPopReleasesOwnershipBeforeTheSourceDisappears` | 断言"释放必须早于 onDisappear"。现在改为**转场确认非取消后**才释放（正是为了消除闪动） |
| `ReaderTabChromeExitTests.testBothReaderOwnersReleaseBeforeCompletionAndReacquireOnCancelledPop` | 同上 |
| `ReaderTabChromeExitTests.testRepeatedCallbacksDoNotReleaseUnrelatedOwnersOrRestoreACompletedExit` | 同上 |
| `TabChromeRegressionTests.testOwnersCannotRevealChromeWhileAnotherReaderOwnsIt` | 断言释放后立即 `isTabChromeHidden == false`；现在延迟 350ms 提交 |

**B 类：本次重构引入的 UI 回归，待修（5 项 + 2 项重复计数）**

| 测试 | 失败行 | 原因判断 |
|---|---|---|
| `FloatingReadingDeskUITests.testContinueRestoresTheSavedParagraphInTheRealWebView` | 207 | `returnFromReader()` 之后断言主页 tab 可点；退出路径已改为覆盖层手势，辅助方法仍按旧导航实现 |
| `FloatingReadingDeskUITests.testNativeReturnCancellationWithLongerSubthresholdDrag` | 388 | 期望 `reader.nativeBookGestureEvidence` 存在；该探针挂在 `ReaderOpeningPresentation` 上，覆盖层路径不再包裹它 |
| `FloatingReadingDeskUITests.testReaderSystemReturnCanCancelWithoutLosingItsSavedParagraph` | 388 | 同上 |
| `FloatingReadingDeskUITests.testReaderSystemReturnCanCancelWithReducedMotion` | 388 | 同上 |
| `ComicPagingBoundaryUITests.testImportedCBZOpensTheNativeComicReaderAndReturnsToItsShelf` | 22 | 漫画阅读器的 `comic.return` 不可点；漫画仍经 gateway → 覆盖层，返回按钮的呈现条件需复核 |

---

## 6. 尚未完成（对照你的 10 条要求）

| # | 要求 | 状态 |
|---|---|---|
| 1 | 完整动画流程（位置/尺寸/圆角/阴影/背景/纸面/正文接管） | 已实现位置、尺寸、圆角、阴影、封面与正文显隐；**纸面展开**未单独做（阅读层自带纸面，随缩放一起出现） |
| 2 | 真正交互式返回、跟手、可取消 | 已实现（`onChanged` 驱动 `p`，松手判定，取消回弹）；**未真机验证** |
| 3 | 不与横向翻页冲突 | 只接管左缘 `UIScreenEdgePanGestureRecognizer`，内容区不参与；**未真机验证** |
| 4 | 主页真正存活 | 已实现（ZStack 同级，不走 pop） |
| 5 | 加载与动画并行、无白屏/假骨架/重复封面 | 占位页已删；封面单独淡出避免重复；**正文 ready 与动画的协调尚未接 `readerOpeningContentReady`** |
| 6 | 动画期无同步 IO / 无高频刷新 | 缩放不触发重排；投影刷新已确认 0.0ms；**未做动画期埋点复核** |
| 7 | 完整回归（进入/退出/连点/取消/翻页/切章/后台/主题） | **只有策略单测**，UI 回归未补齐 |
| 8 | 保留其它入口路由 | 已保留（详情/书架/寻书），仅"进入阅读器"改为覆盖层 |
| 9 | iOS 16–25 / 26+，尊重减少动效 | 使用的 API 自 iOS 14/16 起可用；**未在低版本模拟器验证**；减少动效开关此前按要求删除，现恒不动画降级 |
| 10 | 真实内容/进度/封面验证 | **必须真机**，未做 |

---

## 7. 回退

```powershell
# 回到重构之前（覆盖层尚未引入）
git reset --hard rollback/pre-overlay      # a09b5e3a

# 回到覆盖层骨架、尚无自绘过渡
git reset --hard checkpoint/overlay-skeleton  # 304ac6a3
```

远端同名 tag / 分支 `backup/pre-overlay` 均已推送。

---

## 8. 下一步（按优先级）

1. 更新 A 类 4 个单测到新契约（释放时机、350ms 挂起窗口）
2. 修 B 类 5 个 UI 回归：`returnFromReader` 改为覆盖层退出；探针重新挂载或改断言
3. 把 `readerOpeningContentReady` 接到覆盖层，正文 ready 前不提前展示
4. 补 UI 回归：连点、取消、翻页、切章、后台恢复、主题切换
5. 真机验证 10 条要求，逐项打勾

---

## 9. 风险

- `ReaderTransition` 标了 `@MainActor`，在 Swift 5 语言模式下从 `View` 的初始化器创建属于告警级；若切换到 Swift 6 需改为 `@StateObject` + 显式注入。
- 覆盖层以 `ZStack` 同级方式挂载，`RootTabView` 的 `safeAreaInset` 仍在计算，阅读层靠 `.ignoresSafeArea()` 覆盖；低版本布局未验证。
- 漫画/音频两条子路径仍走 gateway 内部逻辑，本次只改了"谁呈现 gateway"，未改内部；`ComicPagingBoundaryUITests` 的失败说明至少有一处呈现条件依赖了旧的导航上下文。
