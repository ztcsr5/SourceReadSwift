# Build 118 翻页实现只读审查

审查时间：2026-10-31（Asia/Shanghai）。本分片只新增审查产物，没有修改业务代码。与 `pagination-audit.md`、`project-audit.md` 配套使用。

## 结论与验证边界

当前不是一个单独“动画不顺”的问题：窗口内容更新协议、可见页与提交页一致性、模式分流和预热调度都需要分别建立契约。以下代码事实已核实；**未运行 iOS 模拟器、UIKit 集成测试或真机帧率测试，不把静态风险说成视频中某次故障的已证根因**。

证据文件的 SHA-256、模型输入输出见 `flip-model-results.json`。复查命令（项目根目录）：

```text
python docs/audit-20261030-build118/check_flip_model.py
```

该命令实际执行成功，但它仅是 Python 翻译的谓词模型和源码断言，不等于 Swift/XCTest 已通过。

## F1 / P1：邻页更新不会触发五槽窗口刷新

**Observed。** `CoverPageReaderView.swift:255-260` 只以当前 `pageIdentity`、`contentRevision`、样式变化或首次安装决定是否继续。四个邻页 identity 在 `270-276` 才被读取，已在 early-return 之后。`hasPrevious/hasNext` 在 `251-252` 已更新，故能出现“导航允许但实际 host 仍旧”的状态。

**具体触发条件：** 正在读当前章末页 P，下一章原为 placeholder，后台下载/分页完成后下一槽变成真实页；P 的 identity、字体主题 revision 和样式均不变。`ReaderView.swift:689-701` 的 revision 刻意排除章节窗口；caller 在 `2592-2606`、`2739-2753` 确实分别传入当前/邻页 identity，故不是 caller 根本没有提供差异。此时 `apply` 直接返回，邻页根未替换。

**影响范围：** `.cover`、`.pageTurn`、`.pageCurl` 共用该容器。当前页不变期间的邻章到达、第二邻页到达可留下陈旧预览，首次拖向邻页仍见旧占位。当前 identity 或 revision 随后改变可能自行刷新，因此不应宣称所有边界必然永久卡死。

**模型证据：** 当前 P 不变，`next` 从 `placeholder+1` 改 `real+1` 时 guard=false，已安装数组仍是旧数组。应先修“窗口 identity 集合”与“页 root 内容 revision”的契约，而不是加另一个定时重绘。

**补充风险（不另计一个根因）：** 当前页文字、失败状态、听书高亮和文本选择开关等数据发生改变，但 identity/revision 不变，也可能被同一 guard 吞掉。不能简单把所有数据揉进全局 revision，否则可能让每页翻动又重建五个 host；应区分窗口结构 revision 与每页展示 revision。SwiftUI host 内部是否另有订阅更新需集成测试确认。

## F2 / P1：五个可滚动槽位，提交却始终只有一页

**Observed 结构事实；Inferred 条件性可见故障。** `CoverPageReaderView.swift:168-177` 使用 paging scrollView，`395-404` 暴露五页 contentSize；没有实现 `scrollViewWillEndDragging` 去限制落点。`469-486` 只按位移正负半页判定，最终只会 `commit(-1)` 或 `commit(1)`；`ReaderView.swift:2785-2790` 也只将 cursor 加这个单步方向。

**具体触发条件：** 若从中心槽 2 的手势/减速最终落入槽 4（或槽 0），当时屏上内容是 P+2（或 P-2），提交和重居中却把 P+1（或 P-1）变为当前页；`322-330` 强制居中可能表现为内容回跳一页。空邻页、书籍边界亦须覆盖。

**验证边界：** 五页滚动范围与单步提交矛盾确实存在；当前设备/系统上的普通 fling 是否能自然到达最外槽、具体速度与手势条件尚未真机测量。模型只证明 *给定该落点* 时可见页与 cursor 不一致，不证明每次快速翻页都会发生。

**修复决策必须二选一：** 缓存半径保持 2 但可交互范围限定到 ±1；或正式支持多页落点并按物理落点解析 page identity 后提交。不要一边显示 P+2 一边只提交 P+1。

## F3 / P2：三种“模式”实际只剩两种效果，旧仿真路径未被调用

**Observed。** `ReaderSettingsModels.swift:362-376` 仍向用户提供“平移/覆盖/仿真”。但 `ReaderView.swift:2553-2563` 将 `.cover` 和 `.pageTurn` 完全路由到同一个 `coverPagedReaderContent`；`.pageCurl` 路由到 `flipPagedReaderContent`，仍创建 `CoverPageReaderView`，只设 `turnStyle: .flip`（`2592-2616`）。旧 `pageCurlReaderContent` 在全文件只出现一次，只有 `2632` 的声明，没有调用。

**具体条件与后果：** 选择平移/覆盖时实现没有模式差异；选择仿真时是横向 scrollView 加当前 host 左轴 90 度旋转（`CoverPageReaderView.swift:411-416,434-443`），不是旧 UIPageViewController curl。该事实本身不是崩溃，但意味着之前围绕旧 PageCurl 的缓存/交互修补不能自动覆盖当前产品入口，也不能以旧组件测试证明现有入口稳定。

**处理建议：** 先定义并验收三种模式的视觉与手势语义，再保留明确的 backend 路由。共享分页模型是合理的，模式别名应明确标注；不要同时维护不再可达的“仿真修复”代码并把它当作验收对象。

## F4 / P2：预热闭包没有在执行时重新验证手势与任务有效性

**Observed 调度缺口；Inferred 性能风险。** 活跃路径 `CoverPageReaderView.swift:332-359` 在 identity/revision 改变后向主队列投递四个邻 host 的 `layoutIfNeeded`，闭包仅检查 self 存活，没有 interaction/settling guard 或 generation token。`446-452` 的 drag-begin 只通知交互并设置 rasterization，不会使已排队预热失效。

**具体触发条件：** apply 排入预热后、闭包执行前开始下一手势；或连续 apply 多次导致多个预热闭包排队。闭包执行时读取的是最新 `self.hosts`，所以不是“持有已销毁旧 host”的内存错误，但可能对同一最新窗口重复 layout、与手势抢主线程。开销和是否掉帧尚未测量，不应宣称必卡。

**旧路径区别：** `PageCurlReaderView.swift:254-259` 只在入队前检查 `isUserInteracting`；`290-295` 的延迟闭包验证 generation/revision，却未重新检查 interaction。这个缺口也存在，但按 F3 它不能直接作为当前三种分页入口的根因，只是残留实现风险。

**处理建议：** 统一 idle-only warmup + generation + 手势结束重放；新手势应废弃/暂停未开始工作。不要直接去掉预热，否则把开销重新推回下一手势首帧。

## 已读测试与关键缺口

- `ReaderCoverSettlePolicyTests.swift:10-76` 只调用 `contentOffsetX` 旧三槽 overload。实际 controller 使用 `shift` overload。现有测试验证半页阈值，不验证五槽落点、host 内容、commit、重居中和可见 identity 一致。
- `ReaderPerformancePolicyTests.swift:108-126` 只验证时间常量范围及槽数=2×radius+1，不验证交互是否限于一页、不测帧率、不测异步任务执行时机。
- 扫描 `SourceReadSwiftTests/**/*.swift` 未发现任何测试显式引用 `CoverPageHostController`；不能由此绝对断言所有 UI/E2E 覆盖为零，但本测试树未看到该 host 的直接生命周期测试。
- 本轮未执行上述 XCTest（Windows 环境）；模型检查不能替代它们。

### 应补的最小失效测试（规格，不声称已添加到正式测试 target）

1. **邻页单独到达**：装入 P 和 placeholder N，当前/revision/style 不变，仅 N identity/root 改真实页；断言相邻 host 刷新且 offset 不跳。再覆盖仅 ±2 变化、nil→real、real→failure。
2. **五槽提交一致**：宽390，中心 offset780；分别终止于0/390/780/1170/1560，断言屏显 page identity=提交后的 identity；外槽须被限制不可达或正确提交±2。对真实 delegate 顺序执行，不只测 settle enum。
3. **连续/取消手势**：手势中改变窗口、减速中立即反向、commit 后新拖动、回弹动画被中断；每次仅一个 commit，interaction 的结束时刻与 cursor/host 一致，无旧 fallback timer 覆盖新手势。
4. **预热与交互竞争**：测试调度器先 enqueue warmup，再 beginDragging，最后 drain；断言 active 时没有邻页 layout，idle 后只对最新 generation 执行一次有效 warmup。
5. **模式分流产品验收**：三种设置到可见 backend/turnStyle 的映射；若要求不同效果，平移/覆盖不得静默别名；仿真正反向和取消时都不露空白。
6. **内容相同 identity 更新**：当前段听书高亮、文本选择、失败消息改变；断言显示随展示 revision 更新、且不触发分页重测。该项先验证 host 内真实订阅行为再定根因。

## 本分片可交付物

- `flip-audit.md`：本报告。
- `graph-flip.json`：带源码定位与 EXTRACTED/INFERRED 置信标记的语义图分片。
- `check_flip_model.py` / `flip-model-results.json`：只读源码断言与两个反例模型。

建议先锁定 F1/F2 的正确性测试，再讨论动画调参或换框架；否则新动画仍会显示旧页面或提交错误页。
