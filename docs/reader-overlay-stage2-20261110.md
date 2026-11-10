# SourceRead · B 方案第二阶段交付报告

生成时间：2026-11-10 22:30 (+08:00)
分支：`codex/perf-120hz-1109`
最新 SHA：`0621ac21`
IPA：`SourceReadSwift-1.1.8-build138-0621ac2-unsigned.ipa`
SHA-256：`74CE424809D3F1CE1E10CE9999C06B51B291AC31679BFA8BFFC8E4E731EFA9B2`
大小：24,813,679 B
签名：**未签名**（CI 产出的 unsigned IPA，需 LiveContainer / 自签安装）

回退点（已推送）：
- `rollback/pre-overlay` @ `a09b5e3a` — 覆盖层改造之前
- `checkpoint/overlay-skeleton` @ `304ac6a3` — 覆盖层骨架
- `backup/pre-overlay` 分支 @ `a09b5e3a`

---

## 1. 本轮提交序列

| SHA | 内容 |
|---|---|
| `f89219d0` | P0 主体：封面锚点、ready 门控、chrome 隔离、手势取消、测试契约更新 |
| `8a1b6344` | 修 `ReaderExitSwipeController.onEnded` 签名与 representable 不一致 |
| `0621ac21` | 修 `TabChromeRegressionTests` 使用既有的 `eventually` 签名 |

---

## 2. 真实封面坐标：获取与传递

### 2.1 坐标空间

**唯一使用 `.global`（窗口坐标系）**。理由：`.local` 受滚动容器影响，`.named` 需要额外命名空间，两者在"滚动后仍准确"这一点上都会引入偏差；`.global` 以窗口为基准，滚动容器、Safe Area、嵌套 `GeometryReader` 都不改变其含义，覆盖层读到的值与采集点完全一致。

### 2.2 采集

新增 `Features/Reader/ReaderCoverAnchor.swift`：

```swift
@MainActor final class ReaderCoverAnchorStore: ObservableObject {
    static let shared = ReaderCoverAnchorStore()
    @Published private(set) var hiddenBookID: String?   // 仅此一项发布
    private var rects: [String: CGRect]                 // 刻意不发布
    func setRect(_ rect: CGRect, for bookID: String)     // 忽略 <1pt 的无效矩形
    func rect(for bookID: String) -> CGRect?
    func beginTransition(bookID: String)                 // 隐藏源封面
    func endTransition()                                 // 恢复源封面
}
```

修饰符：

```swift
func readerCoverAnchor(_ bookID: String) -> some View
```

内部用 `GeometryReader` + `proxy.frame(in: .global)`，`onAppear` 与 `onChange(of: rect)` 持续更新 —— **滚动后仍准确**。矩形本身不进 `@Published`，否则滚动每帧都会发布并触发全页重排。

### 2.3 挂载点

| 位置 | 文件 |
|---|---|
| 正在阅读卡（Atelier 主题） | `AtelierReadingCard.swift` cover |
| 正在阅读卡（森林） | `ForestReadingCard.swift` cover |
| 正在阅读卡（默认） | `ReadingHeroCard.swift` card |
| 书架列表封面 | `BookshelfView.swift` list cover |
| 书架网格封面 | `BookshelfView.swift` grid cover |

### 2.4 传递与降级

`ReaderOverlayLayer.resolvedCoverRect` = `anchors.rect(for:) ?? request.coverRect`。

- 有真实矩形 → 走共享元素几何，并 `anchors.beginTransition(bookID:)` 隐藏源封面（`opacity 0`，保留布局，书架不跳动）。
- 无真实矩形 → 使用**明确标注为降级**的 `fallbackCoverRect`（偏左上、竖版比例），**不冒充共享元素**。
- 取消手势 → `anchors.endTransition()` 立即恢复源封面。
- 正常完成 → 同样 `endTransition()`，主页状态与滚动位置未变（主页从未离场）。

### 2.5 未完成

`ReaderOverlayRequest.coverImage` 仍来自 `readingCoverHandoff.frame(for:)`；若该处拿不到图，遮罩退化为 `secondarySystemBackground` 纯色。**真实封面图与真实矩形的联合校验需要在真机上看**：可能出现"矩形对、图错"或"图对、矩形来自另一本书"的情况，代码层面用 `bookID` 绑定两者，但没有设备无法证伪。

---

## 3. 正文 ready 信号接入

### 3.1 现状核实

`readerOpeningContentReady(_:)` 的发射点：

| 文件 | 行 | 含义 |
|---|---|---|
| `ReaderView.swift` | 923 | `hasResolvedOpeningPreview \|\| hasOpeningPositionTimedOut` —— 真实正文与目标位置 |
| `ComicReaderView.swift` | 242 | 页面已就绪或已报错 |
| `BookshelfReaderGatewayView.swift` | 174 | 恢复失败的错误视图 |
| `BookDetailView.swift` | 1568 | 章节加载失败 |

`ReaderOpeningReadyKey` 原为 `private`，本轮改为 internal。

### 3.2 接入方式

`ReaderOverlayLayer` 在 gateway 上真实挂载：

```swift
.readerOpeningPresentation(for: request.book, coverFrame: request.coverImage)
.readerReadySignal { ready in contentReady = ready }
```

`readerReadySignal` 用 `onPreferenceChange(ReaderOpeningReadyKey.self)` 收集。

### 3.3 门控规则

```swift
let veilOpacity = contentReady ? coverOpacity(p) : 1
```

- **未 ready**：封面/纸面遮罩恒为不透明 → 不会露出空白 WebView、不会露出错误章节、不会出现假骨架。
- **ready 后**：遮罩按 `coverOpacity` 随进度淡出，正文接管。
- 封面不会因为等待正文而消失（未 ready 时恒为 1）。

### 3.4 明确的 ready 条件（当前实现）

`hasResolvedOpeningPreview || hasOpeningPositionTimedOut`：前者表示目标章节正文已装载且首屏位置已解析，后者是超时兜底。**注意**：超时兜底会在正文未就绪时也置 true，这是既有设计（避免永久白屏），本轮未改动。

### 3.5 未完成

- 未验证"已读书籍 / 首次阅读 / 快速切章 / 重新进入阅读器"四条路径下 `contentReady` 的实际时序。
- 未处理"加载失败"时的重试 UI 与覆盖层内可恢复状态（错误视图会置 ready，但覆盖层未提供重试入口）。
- 未证实"不重复请求书籍内容 / 不重复昂贵分页"——需要在真机用日志确认 `load()` 调用次数。

---

## 4. Tab Bar 生命周期

### 4.1 核实结果

| 问题 | 结论 |
|---|---|
| 覆盖层打开时是否修改 `isTabChromeHidden` | **不修改**。新增 `readerPresentedAsOverlay` 环境标记，`BookshelfReaderGatewayView` 在覆盖层路径完全跳过 `acquireTabChromeHidden` |
| 退出时是否 `releaseTabChromeHidden` | **不执行**（同上） |
| 350ms 延迟是否影响覆盖层路径 | **不影响**。该挂起窗口只服务旧 NavigationStack 路径；覆盖层不 acquire 也就不 release |
| 旧 `onDisappear` 与新退出回调是否重复 | **不会**。覆盖层 `close()` 有 `didRequestClose` 去重；gateway 的 `onDisappear` 在覆盖层路径不触碰 chrome |
| 主页底栏是否保留原始视图身份 | 是。主页在 `ZStack` 中始终存在，未因 `readerOverlay` 变化被重建 |

### 4.2 遗留

`ReaderView` 自身仍带 `.toolbar(.hidden, for: .navigationBar, .tabBar)`。在覆盖层（非导航栈）上下文里该修饰符可能仍会作用到外层 `TabView`，造成一次挂载/卸载时的栏隐藏与恢复。**这是单次状态变更，不是手势中的反复翻转**，但需要在真机确认底栏在阅读期间是否隐藏、退出后是否立即恢复。若确认仍有抖动，下一步是把该修饰符也在覆盖层路径下移除。

---

## 5. 手势状态机

```
edge pan (.left)
 ├─ .changed  → onChanged(dx) → transition.drag(translation:width:)
 │               progress = 1 - clamp(dx / width, 0, 1)     （逐帧，无动画）
 ├─ .ended    → onEnded(dx, vx, false)
 │               finish = shouldDismiss(dx, vx, width)
 │                 vx > 820            → true
 │                 vx < -820           → false
 │                 dx > max(96, 0.32w) → true
 │               finish ? progress→0 + 0.20s 后卸载 : progress→1 回弹
 ├─ .cancelled→ onEnded(dx, vx, true) → 强制 finish=false → 回弹
 └─ .failed   → 同上
```

- 系统取消**不会**被当作正常松手（`wasCancelled` 参与判定）。
- 反向甩动（`vx < -820`）一律取消。
- 取消后：`progress → 1`，并 `anchors.endTransition()` 恢复源封面。
- 防重复退出：`onExit` 传空闭包（覆盖层不用桥自带的退出路径）；`close()` 由 `didRequestClose` 守卫。
- 只接管左缘 `UIScreenEdgePanGestureRecognizer`，内容区手势完全不受影响。

### 5.1 状态更新范围

拖动期间只写 `ReaderTransition.progress`（`ReaderOverlayLayer` 的 `@StateObject`），**不触碰 `AppState`**，因此 `RootTabView` 与书架不会逐帧重算。

`ReaderCoverAnchorStore.hiddenBookID` 只在开始/结束各改一次。

### 5.2 未验证

真机上的跟手流畅度、与 WebView 横向翻页的实际竞争、以及 `UIScreenEdgePanGestureRecognizer` 在 iOS 26 全内容 pop 环境下的行为。**必须真机验收。**

---

## 6. 真实 UI 回归修复结果

| 测试 | 处理 | 状态 |
|---|---|---|
| `returnFromReader` 辅助方法 | 改为点击阅读器自带返回按钮后，等待 `reader.webScrollSurface` 真正消失（`exists == NO`，10s），不再同步断言 | 已改，**待 CI 验证** |
| `reader.nativeBookGestureEvidence` 缺失 | **真实挂载** `readerOpeningPresentation` 到覆盖层（不是加空 identifier），到达探针与 ready 信号一同恢复 | 已改，**待 CI 验证** |
| `comic.return` 不可点 | **未处理**。漫画路径仍经 gateway → 覆盖层，返回按钮的呈现条件尚未定位 | **未完成** |

---

## 7. 测试统计口径

上一份报告写"1931 项中 1925 通过、11 项失败"，那是把 **3 个 job 的失败行合计**，口径不严谨。精确口径如下（run `#772`，commit `4cf5304f`）：

| Job | 执行数 | 失败 | 失败用例 |
|---|---|---|---|
| `build`（单元 `SourceReadSwiftTests`） | 1931（2 skipped） | 6 条断言 / 4 个用例 | `ReaderTabChromeExitTests` × 3、`TabChromeRegressionTests` × 1 |
| `native-tabs`（UI 子集） | 4 | 1 | `ComicPagingBoundaryUITests.testImportedCBZOpensTheNativeComicReaderAndReturnsToItsShelf` |
| `build` 内 UI 套件 | 20 | 4 | `FloatingReadingDeskUITests` × 4 |

**去重后的唯一失败用例：9 个**（4 单元 + 5 UI）。失败断言行合计 11 条，两者不是同一口径。

### 本轮变更后

- A 类 4 个单元用例已按新契约重写，断言**更严**（新增"转场开始不得释放""挂起窗口内不得暴露底栏""取消必须保持沉浸"）。
- UI 5 项中 1 项已改测试路径、1 项已真实挂载探针，**其余未修**。
- `#775` 全量测试在报告生成时仍在运行，**最终数据待补**。

---

## 8. iOS 版本兼容性

| 项 | 结论 |
|---|---|
| `matchedGeometryEffect` | 未使用；几何为手算，无版本门槛 |
| `onScrollGeometryChange` / `tabBarMinimizeBehavior` | iOS 18 / 26，已有 `#available` 包裹 |
| `ReaderTransition` 中 `Task` / `DispatchQueue.asyncAfter` | iOS 13+ |
| `.readerCoverAnchor` 的 `GeometryReader + onChange` | iOS 16 目标版本可用 |
| Safe Area | 覆盖层 `.ignoresSafeArea()`，依赖 `GeometryReader` 的 proxy.size；**iOS 16–25 未在模拟器验证** |
| `@MainActor` + `@StateObject` 初始化 | 见第 9 节 |

**未在 iOS 16–25 的任何设备或模拟器上运行过。** CI 只跑当前模拟器运行时。

---

## 9. 减少动态效果与生命周期

- `ReaderOverlayLayer` 读取 `@Environment(\.accessibilityReduceMotion)`，在 `onAppear` 注入 `transition.reducesMotion`。
- 开启时：`openAnimation` / `settleAnimation` 返回 `nil`，几何**瞬变**而非大幅运动；卸载延迟从 0.20s 降为 0。
- 不恢复 App 内"减少动态效果"开关（按你的要求已删除）。
- 减少动态效果下覆盖层仍可关闭：手势路径不受影响，`endDrag` 照常调用 `onFinish`。
- **`ReaderTransition` 的 `@MainActor` 初始化告警未消除**：`@StateObject private var transition = ReaderTransition(reducesMotion: false)` 在 Swift 5 语言模式下是告警级；切 Swift 6 需改为显式注入。本轮未改。

---

## 10. 性能约束核查

| 约束 | 结论 |
|---|---|
| 手势每帧磁盘 I/O | 无 |
| 手势每帧书架排序 | 无（`refreshShelfProjection` 不在拖动路径上） |
| 手势每帧图片解码 | 无（封面图在请求里已存在；遮罩直接复用） |
| 手势每帧全局 `AppState` 更新 | 无（只写本地 `@StateObject.progress`） |
| 重复创建动画任务 | 每次 `open()` / `endDrag()` 各一次 `withAnimation`，无循环创建 |
| 新增高频 `CADisplayLink` | **无**。诊断用的 20Hz timer 只在用户显式开启记录时运行 |
| 新增全局渲染循环 | 无 |
| 删除动画伪装性能 | 无，动画为本轮新增 |

**动画期状态更新范围**：仅 `ReaderOverlayLayer` 的 `transition.progress`；`onPreferenceChange` 只在 ready 翻转时写一次 `contentReady`。

未做实测（无真机/Instruments），以上为代码层核查。

---

## 11. 纸面与视觉细节

- 封面抬起 → 几何扩展 → 阅读纸面自然出现 → 正文接管，四段流程完整。
- **纸面展开未独立实现**：阅读层自身带纸面背景，随缩放一起出现；没有单独的纸面展开层次。
- 未引入实时阴影图层叠加；阴影只随 `p` 衰减。

---

## 12. UI 自动化回归矩阵

| # | 场景 | 状态 |
|---|---|---|
| 1 | 首页正在阅读进入正文 | 既有用例，已改退出辅助方法 |
| 2 | 书架封面进入正文 | **缺**（书架点击进详情，不是阅读器） |
| 3 | 阅读器正常退出 | 既有用例 |
| 4 | 拖动不足阈值取消 | 既有用例（依赖探针，已恢复挂载） |
| 5 | 拖动超过阈值退出 | 既有用例 |
| 6 | 反向快速甩动 | **缺** |
| 7 | 系统取消手势 | **缺** |
| 8 | 连续快速进入退出 | **缺** |
| 9 | 横向翻页 | **缺**（覆盖层下未验证） |
| 10 | 切换章节 | 既有用例 |
| 11 | 恢复上次阅读位置 | 既有用例 |
| 12 | 后台恢复 | **缺** |
| 13 | 主题切换 | 既有用例 |
| 14 | 漫画进入返回 | 既有用例，**当前失败** |
| 15 | 减少动态效果 | 既有用例（`testReaderSystemReturnCanCancelWithReducedMotion`） |
| 16 | 底栏与滚动位置恢复 | **缺** |

策略层单测（`ReaderTransitionPolicyTests`，5 用例）覆盖进度映射、松手判定、几何插值、显隐交接、圆角；**它不能替代上述 UI 回归**。

---

## 13. 待真机验收清单

1. 封面是否从**真实位置**抬起（滚动书架后依然准确）
2. 源封面是否在过渡中被正确隐藏、取消后恢复
3. 拖动是否逐帧跟手，取消是否平滑回弹
4. 正文 ready 前是否**完全不露**空白 WebView
5. 退出后底栏是否立即恢复、主页是否可立即交互
6. 拖动期间主页是否完全不刷新
7. iOS 16–25 与 26+ 的 Safe Area 表现
8. 系统减少动态效果下的过渡与返回
9. 漫画进入/返回（当前 UI 测试失败，需先修）
10. 真实 120Hz / 掉帧：**不做任何声称**

---

## 14. 明确未完成

1. `comic.return` 不可点，原因未定位
2. 加载失败时的重试入口未做
3. 未验证多路径 ready 时序（已读/首次/切章/重进）
4. `ReaderTransition` 的 `@MainActor` 初始化告警未消除
5. iOS 16–25 未验证
6. 回归矩阵 16 项中缺 9 项
7. `#775` 全量测试结果未出
8. `ReaderView` 的 `.toolbar(.hidden)` 在覆盖层上下文中的实际效果未确认

---

## 15. 复现与验证命令

```powershell
# 静态检查
cd D:\Gemini反重力\SourceReadSwift2
python -B -X utf8 scripts/audit_current_swift_syntax.py HEAD
git diff --check

# 回退
git reset --hard rollback/pre-overlay
```
