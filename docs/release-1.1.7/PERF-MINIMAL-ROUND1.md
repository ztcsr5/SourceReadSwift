# 第一轮最小性能修复 · 2026-11-04

## 状态与范围

- 基线：`1e538688179f1faddb927552506d8a794c6ec4da`，`codex/floating-reading-desk`。本轮修改留在工作树，未提交、推送、触发 CI 或打包 IPA。
- 仅处理显式诊断、阅读进度及同链路历史写入、退出时保存与全局通知合并。保留原 ProMotion plist、导航版本策略、首页、玻璃、动画参数及主题。
- 既有 7 个脏文档及旧备份不动。原始 1111 个受控文件快照、工作树 diff/status、日志摘要在 `F:/SourceReadSwift/perf-minimal-117/baseline-20261103T162743Z`。

## 修改前证据

1. `ReaderView` 在阅读器出现时无条件 begin、退出时 end；旧采样器在整个阅读生命周期请求 80–120Hz，引用计数可能使后续实例继续持有 link。
2. `ReaderView` 的 700ms 防抖完成后仍在 MainActor 调用同步进度编码/写盘；`onBookRead` 随后同步保存阅读历史。退出时 `recordReadingSession` 还会同步保存含本地正文的完整书架。
3. 阅读历史一次更新有 remove/insert 等多次发布；成功写入仍给 `@Published lastError` 重复赋 nil。AppState 对每个子 Store 通知各起一个 Task 再全局广播。
4. 找到原始模拟器 XCTest 日志：`Progress canonicalBytes=4124384 sidecarBytes=149 elapsedIncludingReload=0.05088794231414795`。基线与该日志提交的 `BookshelfStore.swift`、`BookshelfPersistence.swift` 完全相同。
5. 第 4 项约 50.888ms **包含更新、读 sidecar、完整重载**，不是独立编码耗时，不是当前 iPhone 13 Pro 数据，也不能据此证明主线程卡顿根因。原始日志路径、大小、SHA256 和边界已存 `BEFORE_EVIDENCE.json`。本轮没有可用的 Swift 编译器、Apple SDK 或 Instruments，不能给出新的运行耗时改善百分比。

## 决定与后果

### A. 诊断只由用户显式启动

- 删除阅读器自动采样调用；旧帧率类型仅保留历史记录兼容，不再创建 CADisplayLink、观察生命周期或保存引用计数。
- 唯一 link 由 AppFrameProfiler 的私有单例持有。重复 start 幂等；手动停止、30 秒上限、willResignActive 均 invalidate link 并取消截止 Task；前台恢复不自动开启。
- 诊断离开设置页后允许在其他页面继续，**这是显式授权的最多 30 秒诊断窗口，不是页面泄漏**。设置文案写明这一点。
- 诊断不设置 preferredFrameRateRange。回调频率可能降低，不代表界面变慢；报告不再把回调次数称为呈现帧或显示 FPS。
- 滚动回调累计也默认关闭，只在同一显式诊断窗口开启，新窗口清零，停止后只落盘一次。旧阈值累加器仅用于兼容测试，不再展示为“掉帧率”。

### B. 仅将已确认的阅读保存链路异步化

- 复用项目已有 ChapterContentCachePersistence 的串行队列模式，不引入依赖或更换存储格式。
- 书架进度与退出时快照在同一后台 FIFO 上编码及写盘；历史记录使用自己的有序后台队列。
- 同步 load/save、删除、恢复与异步写入共享队列屏障。重新打开存储会等待先前写入；删除及完整快照清除 sidecar 后，旧排队写入不能反过来覆盖它。
- 进度依然立即更新内存，保留原 700ms 防抖。磁盘完成异步通知，修订号阻止旧完成回调覆盖新错误状态；失败可见且不重复发布未变化的 nil。
- 退出时书架只发布一次完整 session 更新，保留置顶顺序；历史回调使用实际阅读的书，而不是可能置顶的另一书。
- inactive 时取消待防抖任务，在有限系统后台执行令牌下先捕获最终位置，再异步等待书架与历史队列完成。Root 也为已离开阅读器的待写入提供收尾。完成及到期都幂等释放，不续期、不常驻保活。
- 已结束的 Reader 会话不再在随后场景切换中写旧位置。
- 普通书架结构变更、导入、备份/恢复仍保留原同步语义；本轮没有将所有存储全盘异步化。它们的屏障可能等待已有写入，不宣称所有主线程等待都消失。
- 任意时刻强杀、磁盘故障或系统拒绝/提前收回后台时间，不能承诺尚未完成的异步写入已经持久化。后台/快速切书/重启的实际表现仍须真机验收。

### C. 通知只合并，不取消观察

- 所有现有 11 路子 Store 订阅保留；已确认它们均为 MainActor 隔离。去掉每条通知新建的 Task，同一轮只安排一次全局通知，读取最终一致状态。
- Store 的直接观察仍立即生效；导航的 `isTabChromeHidden` 发布不进入该合并器。没有更换 AppState、导航或观察架构。

## 文件清单

根目录为 `D:/Gemini反重力/SourceReadSwift2/`：

| 文件 | 目的 |
|---|---|
| `SourceReadSwift/Shared/Performance/AppFrameProfiler.swift` | 单例显式、有上限、可释放的回调诊断，不请求高频地板 |
| `SourceReadSwift/Shared/Performance/ReaderFrameRateSampler.swift` | 退为旧诊断读数兼容，不再调度 |
| `SourceReadSwift/Shared/Performance/ReaderScrollPerfMeter.swift` | 业务回调统计默认关闭 |
| `SourceReadSwift/Features/Settings/AppFrameProfilerSection.swift` | 说明窗口、停止方式及读数边界 |
| `SourceReadSwift/Features/Settings/ReaderPerformanceDiagnosticsView.swift` | 移除真实 FPS/掉帧率误导标签 |
| `SourceReadSwift/Core/Storage/BookshelfPersistence.swift` | 有序后台进度/快照，保留同步屏障、加入写入 signpost/探针 |
| `SourceReadSwift/Core/Storage/BookshelfStore.swift` | 阅读保存入队、一次 session 发布、修订号处理完成 |
| `SourceReadSwift/Core/Storage/ReadingHistoryStore.swift` | 相关历史链路后台写入、单次发布、保留删除屏障 |
| `SourceReadSwift/Core/Storage/ReadingWriteBackgroundLease.swift` | 有限 OS 后台写入令牌，完成/到期幂等释放 |
| `SourceReadSwift/App/AppState.swift` | 合并全局通知与后台写入收尾 |
| `SourceReadSwift/App/SourceReadSwiftApp.swift` | 非 active 时收尾已入队写入，原 ProMotion 逻辑不变 |
| `SourceReadSwift/Features/Reader/ReaderView.swift` | 取消自动采样，后台捕获位置，防止结束会话重写 |
| `SourceReadSwiftTests/ExplicitFrameDiagnosticsTests.swift` | 新增 4 项原生诊断生命周期用例 |
| `SourceReadSwiftTests/OrderedReadingPersistenceTests.swift` | 新增 7 项真实临时文件/顺序/通知/失败恢复用例 |
| `SourceReadSwiftTests/ReaderScrollPerfMeterTests.swift` | 原断言保留，显式开启诊断后测累计 |
| `SourceReadSwiftTests/BookshelfProgressPerformanceTests.swift` | 原数据断言保留，直读磁盘前走重载屏障 |
| `SourceReadSwiftTests/BookshelfStoreTests.swift` | session 测试清理目录前等待异步写入 |
| `scripts/test_perf_minimal_scope.py` | 10 项本机源码边界检查，明确不是 SDK/设备测试 |
| `CHANGELOG.md` | 未发布变更与验收边界 |
| `docs/release-1.1.7/PERF-MINIMAL-ROUND1.md` | 当前检查点、决定、证据、回滚 |

新增依赖：无。既有同步存储入口及 JSON 格式保持兼容；Store 的阅读保存返回时仅保证已发布内存及已入队，完成持久化通过 waitForPendingWrites 或重载屏障确认。

## 验证

```powershell
Set-Location 'D:\Gemini反重力\SourceReadSwift2'
python -B -X utf8 -m unittest discover -s scripts -p 'test_*.py' -v
git diff --check
```

- 本机 32 项通过：新源码约束 10、书台隔离 10、启动策略 6、原阅读设置流程 4、真实本地 Chromium/Node 跳转回归 2。
- 最初 8 项源码约束在原实现为 RED（7 失败、1 缺少后台边界）；修改后 GREEN。日志保存在外部证据目录。这是源码合同红绿，不是原生行为红绿。
- Swift tree-sitter 语法解析通过；它不是 Swift 编译、类型检查或 Apple SDK 验证。
- 新增 11 项原生 XCTest **未运行**：重复 start/stop、后台停止与不重启、期限、正常滚动不采样、后台线程写入、快速切书、删除不复活、历史写入顺序、合并通知、置顶 session 身份、失败恢复。保留原位置及 sidecar 数据断言。
- 写入 signpost：`bookshelf.progress.write`、`bookshelf.snapshot.write`、`reading-history.write`；原生测试会输出 enqueueMs/totalMs。尚无新运行数字。
- 冻结文件与 7 个既有脏文档逐文件哈希核对保持原样。未修改版本、工程配置、书台、主题、玻璃、动画或导航布局；无 IPA。

### 尚未验收

1. iOS 16/18/26+ SDK 编译与新增原生 XCTest。
2. iPhone 13 Pro 快速 A→B→A、滑动/翻页后立即后台、锁屏、重启后的章/段恢复。
3. 真实 OS 后台到期/拒绝场景的令牌释放与写入完成，LiveContainer 与独立安装需分开记录。
4. 正常使用无采样 link、显式诊断最多 30 秒、后台立即停止的真实设备生命周期。
5. Instruments 帧时间、提交/渲染卡顿、输入延迟与实际 ProMotion 调度。没有稳定 120fps 或真机耗时改善声明。

## 回滚

外部 `scripts/rollback_round1.py` 使用基线 ZIP 和最终文件 SHA256，仅恢复本轮文件；若文件后来再次被改动则拒绝覆盖。先运行不带 `--apply` 的检查，通过后才执行同命令加 `--apply`。不 reset/stash/clean，不动既有脏文档、旧包或备份。

到此停止；不自动扩展热点、不推送 CI、不打包。
