# 阅读体验审查 · 2026-11-08

## 结论与证据边界

本轮处理用户第 3、4、7 项。已有工作树包含多轮历史修复，本报告只把本轮新增且能定位的变化计为成果。Windows 没有 Xcode；浏览器验证和 Swift 语法树检查不能替代 iOS 编译、WebKit、真机帧时间验证。

### 第 3 项：开卷遮罩缺少当前书籍上下文

- 现象：实际源码仍显示呼吸徽标、随机引语和无限循环动画；导航到达之前仅显示纸色背景。它既不能辨认当前书籍，也与即将出现的正文版式不连续。
- 修复：`ReaderOpeningStatus` 从第一帧显示真实书名、作者、当前章节；正文区域使用静态段落骨架，等待状态只加文字。删除品牌图标、随机引语、呼吸动画和旋转加载控件。正文完成定位并且导航到达后仍立即撤下遮罩，保留原来的 180 ms 淡出，减动效下无淡出，不增加人为展示时长。
- 初次加载和备用入口使用同一个过渡；返回时的真实书籍封面仍保留。
- 深色：`ReaderView.readerIsNight` 实际取 `background.isDark`，项目未使用 `reader.nightMode` 或自动夜间键。发现每本书背景原本要等 `ReaderView.onAppear` 才写回全局设置；过渡现在先读取 `ReaderOverrideStore` 中该书的背景，避免全球白色、该书深色时闪白。非法全局值的回退与正文统一为 `.paper`。
- 返回：`.allowsHitTesting(didReveal)` 和 `.accessibilityHidden(!didReveal)` 在 `.overlay` 之前，只限制其底层正文；返回按钮属于后加的 overlay，并未被这两个修饰符包住。未因此改动导航行为；慢加载真实点击返回仍需原生 UI 验收。
- 原生新增 `ReaderOpeningTransitionTests`：320/390 宽第一帧依书籍内容变化、重复渲染稳定、等待状态不移动标题、每书深色覆盖优先；浅色 320/390 和深色 390 图片使用 `XCTAttachment.keepAlways` 保存。它替代要求旧徽标/引语存在的过时 Python 字符串断言。

### 第 4 项：章节到达时标题被摘掉，标题锚点还会停止惯性

- 决定性证据：`scripts/test_reader_chapter_arrival.py` 提取生产 `WebReaderHTML.shell` 在 Chromium 中运行，不复制实现。当前章正文后接下一章加载标题，滚到标题可见，再送入生产 `setContent` 增量。
- 修前普通底距 24：`accepted=true, sameHeading=false, detached=true, commands=0`；标题处在 y=713.75，加载完成时真实标题节点被摘掉。
- 修前锚点场景（底距 900 用于使标题处于阅读锚点，非声称手机默认底距）：`sameHeading=false, detached=true, commands=2`，即使标题文本和版式不变也执行了两次 `scrollTo`。这是可复现的惯性中断路径，尚不等于用户全部卡顿的唯一根因。
- 根因：`setContent` 只按整章签名决定重建；加载占位变正文使签名变化，原章连同标题被替换。当阅读锚点位于这章标题，还走到 `stopScrollAnimation` 和 `restoreAnchor`。
- 修复：仅在原节点明确为加载占位、标题文字和首章角色均不变时，保留原 section/heading，填入其后的正文。若锚点位于这个不变的标题，视为前缀未变，不调用滚动控制。前面章节变化、标题变化、已显示正文变化仍沿用严格锚点恢复。
- 修后同一测试两个场景均通过：标题与 section 没被摘掉、标题位置误差 ≤1 px、新正文确实出现、0 次 `scrollTo`。
- 原生 `ReaderScrollCadenceTests.testNextChapterBodyArrivalPreservesItsVisibleTitleAndInertia` 用实际 Swift payload builder 和 WKWebView 重放相同两个场景；待本轮同 SHA CI 验证。

### 第 4 项另一个明确缺口：后台预缓存没有归属

- `precacheDiskWindow` 原本每次跨章/近底触发都新建无句柄的 detached 任务，向前 5 章与已有正文预取队列重叠；退出/切窗不会取消，也未在请求返回后阻止迟到保存。缓存命中只避免已完成的请求，不能阻止同时启动的重复请求。
- 新增 `ReaderBackgroundChapterPrecache`：同一窗口请求去重，窗口变化和退出取消；即使下层忽略取消，返回结果也不会继续提交。前向章节只归既有正文队列，滚动模式的后台队列只预备后退方向；分页模式的既有队列已负责两侧，因此不再另外发起磁盘队列。
- 每书半径与已缓存内容保留；向前窗口仍至少 5 章。后台不再把反向章节插到当前 DOM 上方。
- 新增原生异步测试：重复近底请求只加载/提交一次，取消后迟到结果不保存且不发下一章，新窗口先完成后旧窗口迟到不能写回。尚未在 Windows 运行原生测试。
- 限制：这个变化消除确定的重复前向请求和过期保存路径；没有用它宣称主线程缓存保存耗时、全部网络压力或所有阅读卡顿都已解决。

### 第 7 项：翻页后的额外主线程挂载

- 源码证据：`CoverPageHostController.install` 同步创建/加载全部 5 个 UIHostingController，包括屏外 ±2 页；下一次主队列任务又一次 layout 全部页面。滑动翻页虽然由 UIKit 位移，完成手势后仍要承担这部分开销。
- 修复：安装只挂载当前页及 ±1；屏外 ±2 分开在空闲队列挂载，新拖动、窗口替换、销毁会使旧 warmup 失效。原可见邻页、提交时序、快速二次滑动与 teardown 逻辑保留。
- 新增 `ReaderPageHostingTests.testSlideMountsOnlyVisibleNeighboursBeforeAnImmediateDrag`：真实控制器安装后只有 3 个子页；立即拖动、排空主队列仍只有 3 个；当前页确实位移 -100；取消后空闲恢复到 5 个。
- `CADisableMinimumFrameDurationOnPhone` 现有配置已经打开；`FrameRateCoordinator.apply` 只是记录能力，没有公开的 UIWindowScene 帧率 setter。不能把 preferredRange 或标称 120 Hz 当成实际 120 FPS。此轮未新增持续 display link 强刷，也未声称真机帧率目标已达成。

## 本地验证

```powershell
python -B -X utf8 -m unittest discover -s scripts -p test_reader_chapter_arrival.py
python -B -X utf8 -m unittest discover -s scripts -p test_web_reader_visible_position.py
python -B -X utf8 -m unittest discover -s scripts -p test_release118_quality.py
python -B -X utf8 -m unittest discover -s scripts -p test_product_quality_scope.py
```

分别为 1 项（2 个场景）、2 项、13 项、21 项，均 `OK`。章节到达用例先红后绿；保留原断言，没有以重跑同代码碰绿替代修复。

9 个本轮涉及 Swift 文件的 tree-sitter 新增语法错误为 0，记录 `READER-SYNTAX.json`；这不是 SDK 类型检查。

首轮 `ff0f398` / run `42398969413` 已在 iOS 26 通过 `ReaderBackgroundChapterPrecacheTests`（3）、`ReaderScrollCadenceTests`（5）、`ReaderPageHostingTests`（4）。开卷两项图像测试失败：ImageRenderer 没有绘出 ScrollView 的 UIKit 内容；后续改为真实窗口挂载再截图，保留全部行为断言，等待新候选验证。实际阅读 UI 流程仍有失败，不能用这些单项通过声称全链无问题。最终结果由主任务在同 SHA 构建后登记。

## 影响与回滚

无持久化格式迁移。保留书籍进度、回退锚点、字体/纸色、自定义背景、减动效与旧预取队列。更改仅限阅读过渡、章节 DOM 到达、预缓存任务归属和屏外页挂载。

本轮未提交，由主任务统一形成 Conventional Commit；提交后以对应 commit 的 `git revert <READER_FIX_COMMIT>` 回滚，不 reset 或 checkout 整个文件以免丢失本轮前的历史未提交修改。
