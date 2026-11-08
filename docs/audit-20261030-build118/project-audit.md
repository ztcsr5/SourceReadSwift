# 全项目广度审查与交接地图（Build 118）

基线：`D:/Gemini反重力/SourceReadSwift2`，HEAD `5686485`；118 主改 `bffedba`。审查日期：2026-10-30（Asia/Shanghai）。

## 结论

**不宜把整个项目推倒重写；应冻结现有书源引擎和已验证解析语料，集中重建阅读会话状态、渲染器边界与产品验收门禁。** 当前问题不是“又少改了一个常量”：阅读器仍由超大 SwiftUI View 同时调度章节窗口、分页、手势、缓存、朗读、持久化与工具栏。CI 主要证明编译/算法回归，不证明持续翻页体验。交接文档与代码已显著脱节，容易让后续 AI 修错执行路径。

事实标记：**Observed**＝本次直接读取代码/配置/本地 git；**Inferred**＝据代码推断的工程风险，尚非真机复现；**历史声称**＝旧报告/聊天记载，不等价本次验证。本文未执行 iOS 编译、XCTest、真机操作或联网刷新 git refs。

## 范围与规模

Observed：枚举整个 App/Core/Features/Shared 目录、测试文件名和构建配置；精读 App 层、ReaderView 关键状态/渲染路由/预热/生命周期、SourceEngine 并发入口，读取 README、PROJECT_HANDOVER、PROJECT_FULL 的目录与末轮章节、三个 Actions workflow、现有 ci-log 元数据与最新提交摘要。未逐行审查全部 77,518 行 Swift；未遍读大型测试 fixture；视频和聊天详细审计由同一审查任务的其他报告承担。

- 应用：195 个 `.swift` 文件，77,518 行（PowerShell Get-Content 统计）。
- 测试根目录：166 个 `.swift` 文件；这不是已执行测试数量。
- Reader 目录：25 个 Swift 文件；ReaderView.swift：7,606 行，全文件 93 行 `@State` 声明。
- 其他集中点：JSCoreRuntime 5,670 行；SourceManagerView 2,687 行；JSONRuleExtractor 2,563 行；SourceEngine 2,085 行。

## 1. 主要发现（按优先级）

### P1：发布产物未受 XCTest 成功门禁约束，且没有 UI 翻页验收目标

**Observed**：`project.yml:90-101` 只有 `bundle.unit-test`，未定义 UI-test target。`.github/workflows/ios.yml:54-69` 在“第一个可用 iPhone 模拟器”跑 XCTest；`.github/workflows/unsigned-ipa.yml:7-38,92-97` 是独立 push 工作流，只 build Release 然后发 IPA，没有 `needs` / `workflow_run` 成功约束，也不运行测试。`ios.yml` 没有上传 xcresult/测试日志的步骤。`source-rows-probe.yml` 专注书源 rows/TOC/URL，仅手动触发。

**Inferred**：打包绿灯并不代表相同 commit 测试通过；即使 1,356 条 XCTest 全绿，也无法证明 UIKit 连续拖动、SwiftUI 重建、跨章异步回调、设置叠层或 ProMotion 帧时延正确。Reader 测试已有价值，但大多是 policy/geometry/文本构造断言，不应被包装成产品体验验收。

**建议**：同一 commit build→unit→reader UI smoke→package 的显式流水线；保存 xcresult、OS/设备/Xcode 版本、IPA hash、视频、帧时间采样；iOS 16/17 至少两套设备门禁；将快速翻页、反向取消、跨章补页、菜单/设置、字号变更后锚点保持列为发布阻断项。

### P1：阅读器状态所有权过于集中，拆文件之前先拆状态契约

**Observed**：`ReaderView.swift:51-244` 同时保存 chrome、页码、可见段落、章节窗口、加载错误、重试、缓存签名、geometry settled、prefetch/warmup generation、TTS、autoScroll。`:1855-2052` 调度预取/并行分页；`:2463-2505` 处理手势锁与延期 rebuild；`:2930-2951` 预热富文本；`:6324-6348` 再有一条分页 rebuild 入口。`:6704-6750` 还在同文件定义带 NSLock 的富文本缓存。AppState 被 Reader 作为整个 EnvironmentObject 观察（`:8`）。

**Inferred**：多处逻辑共同写同一组页码/章节/缓存，很难只从单个 policy 测试确认原子性；一轮改手势可能间接改变窗口补页、TTS、持久化时序。7,606 行不是 bug 的证据，但状态跨域混合与多条重建入口是真正的维护风险。

**建议**：引入一个 MainActor `ReaderSession`，唯一管理稳定 ReadingAnchor、窗口 revision、当前 page identity、交互 phase；PaginationService 只接收不可变快照并返回带 generation 的结果；各 RenderSurface 只发 begin/cancel/commit，不直接改变章节；Chrome/TTS/Settings 独立子系统。不要只把同一 View 的方法机械拆成 extension。

### P1：实际渲染路由与旧文档/旧组件名称不一致，存在“修到非主路径”的风险

**Observed**：`ReaderView.swift:1584-1588` 的滚动正文实际为 `WebScrollReaderView`（WKWebView）；`:2553-2563` 将 `.cover` 和 `.pageTurn` 都指向 cover surface，将 `.pageCurl` 指向 `flipPagedReaderContent`；`:2592-2614` 的仿真同样是 `CoverPageReaderView(turnStyle: .flip)`。`:2632-2666` 仍保留旧 `pageCurlReaderContent`，但当前 mode switch 没有选择它。`.pageTurn` 不是正在使用 UIPageViewController.scroll 的主分支。现有注释仍写 three-slot / 5-page，而实际参数已含 ±2 slot、预热 radius 12（`:2575-2606,2930`）。

**Inferred**：后续 AI 若根据“pageCurl”名字直接修 PageCurlReaderView，可能对用户实际仿真模式没有作用。PROJECT_FULL 的“TextKit 长文滚动”叙述不能作为当前架构真相。

**建议**：先建立四模式→真实组件→状态来源→事件回传表，保留 feature flag 对照后再删旧 renderer；禁止同时保留两套无明确激活规则的实现并持续打补丁。

### P2：并发已有隔离努力，但生命周期没有完整任务清单

**Observed**：分页 warmup 使用不可变 context、withTaskGroup、generation 与 signature 回写检查（`:1911-1994`），值得保留。富文本 cache 有 NSLock 和签名检查（`:6704-6750`），不能简单认定为无锁数据竞争。另一方面，`:2930-2951` 的 DispatchQueue 预热无取消句柄；`:1112-1134` onDisappear 取消若干任务，但未取消 `geometrySettleTask`、`paginationWarmupRestartTask`、`chapterSeekTask`；`:1882-1889` cancelPaginationWarmup 只取消当前 warmup，并没有取消 restart task；`:2043-2052` restart 可以稍后重新调用 warmPaginationCache。Gateway `:361-373` 的正文预热使用未保存句柄的 Task.detached。

**Inferred**：退出/换书后仍可能做失效计算或重启预热；是否可见错页需要生命周期测试，本文不宣称已真机复现。多线程 TextKit 的安全性需要专属栈、不可变 UIKit 属性访问与 sanitizer 验证，不能用注释“safe”代替证据。

**建议**：集中持有 SessionTaskBag；离开/换书统一 cancel + epoch 增长；所有提交比较 bookID/sessionID/layoutRevision；预热限制队列并合并重复任务；保留缓存锁和独立 TextKit stack，先测试再重写。

### P2：AppState 的全量广播放大无关 UI 更新

**Observed**：`App/AppState.swift:163-258` 把书架、章节缓存、下载、RSS、source health、诊断历史、阅读历史、Discover 等 child objectWillChange 再转发到单个 AppState；Reader 观察这个 AppState。`:116-145` 还在 MainActor 上同步读取/解析导入文件。

**Inferred**：后台缓存/诊断/下载变化可能让整个 Reader body 失效；长文件导入可能阻塞主线程。没有 Instruments 数据，不能把任何一次卡顿唯一归因为它。

**建议**：AppState 保留 composition root，Reader 仅订阅阅读会话所需 observable slice；后台导入解析返回 immutable result 后再在 MainActor 提交。

### P2：交付基线、版本文档和 git 上游存在三种漂移

**Observed**：`project.yml:33-34`＝1.0.118/118；`PROJECT_HANDOVER.md:4-7`＝1.0.93/94；`PROJECT_FULL.md:4-11`＝1.0.85/86，而正文 `:64-75` 仍是 1.0.30/31 和旧规模；README `:21-22` 仍指向另一个目录/旧分支。

本次 `git rev-list --left-right --count 'HEAD...@{upstream}'` 输出 `13 10`；本地分支 `codex/swift-v2-lifetime-reader`，本地保存的 upstream ref 已分叉。全 refs 图显示部分 114/112 类似主题存在不同 commit。**这只证明本地 refs 视角，不代表实时远端**；未 fetch，未合并、重置或推送。

**建议**：交接唯一 manifest 固定 repository path、branch、HEAD、Build、IPA SHA256、CI run headSha、已复现/未复现；提交边界一致后再处理分叉。不要自动 pull 或 reset，更不要把旧报告的“已完成”沿用成当前状态。

### P2：可复现构建还未锁定完整工具链

**Observed**：`project.yml:10-19` 三个依赖使用 from 范围；`git ls-files '*Package.resolved'` 无结果。两个 workflow 使用 macos-15、brew install xcodegen、runner 默认 Xcode，未固定 Xcode 版本；模拟器选择“第一个可用 iPhone”。

**Inferred**：相同源码未来可解析到不同依赖/SDK/模拟器环境，难以区分 UI 回归与环境改变。建议固定 toolchain/依赖解析、记录构建环境，别在本轮直接升级依赖。

## 2. 全局模块地图与保留边界

| 模块 | 职责 / 主要入口 | 处置建议 |
|---|---|---|
| App | SourceReadSwiftApp → RootTabView；AppState 注入 stores、engine | 保留入口/DI，缩窄观察广播 |
| Features/Bookshelf | 书架、本地书、BookshelfReaderGateway 加载目录和正文后创建 Reader | 保留功能，抽出 ReaderLoader / Session factory |
| Features/Discover | 搜索、BookDetail、SourceWriting；接 SourceEngine | 本轮不重写，隔离与阅读器变更 |
| Features/Reader | 阅读会话、4 模式、排版、翻页、TTS、漫画/音频/视频 | 优先重整状态契约；媒体播放器不与文本翻页一起重写 |
| Features/SourceManager | 导入/分组/校验/规则编辑 | 现有功能保留，后续单独拆 UI 与 editor state |
| Features/Settings | 全局设置、备份、WebDAV、字体等 | 保留数据格式与迁移，阅读设置可抽独立组件 |
| Features/RSS/Verification | RSS 阅读和验证输入 | 保留，与正文阅读状态隔离 |
| Core/Engine | SourceEngine 协议，LegadoSourceEngine 全链路编排 | 保留协议、网络注入和测试资产；独立审查共享状态 |
| Core/Rules + JavaScript | CSS/JSON/XPath/JS、Legado host bridges | 核心资产，禁止为翻页问题顺便重写 |
| Core/Network | URLSession、WKWebView、cookies、请求选项、限流、WebDAV、LAN 写源 | 保留行为与测试，限制主线程 UI 边界 |
| Core/Storage + Models | 书架/章节/TOC/下载/历史/书源等持久化 | 保留现有 schema，未来迁移需独立兼容测试 |
| Core/Import/Compression/Audio/Security/Environment | TXT/EPUB、压缩、播放、凭据与环境 | 保留；导入重负载移出 MainActor |
| Shared | DesignSystem、Foundation、Diagnostics、Performance | 保留 signpost/fps/scroll meter，但采样要接入验收 |
| Tests / Fixtures | policy、排版、解析器 corpus 和源回归 | 保留；补 UI 轨迹与并发组合测试，不以改断言代替验证 |

上述是目录/依赖地图，不是所有模块都经过安全或业务正确性审计。project.yml 的应用 target 直接包含整个 SourceReadSwift 目录（:24-25）；这些目录目前并非独立编译模块。

## 3. 118 的证据分层

1. **本次 Observed**：本地 HEAD/版本与 118 改动列表已核对。bffedba 改 6 文件，215 insertions / 156 deletions；5686485 继续改 geometry 单测断言。`ci-log/latest/ios` 没有文件；ci-log 内元数据举例 `job.json` 为 2026-09-03、head `9e1fd6f`、failure；`run-33907291067-jobs.json` 为 2026-09-04、head `bc5c138`、failure。这些不是 118 的测试证据。
2. **聊天历史证据（另见 chat-build118.md）**：末轮 step 5073 声称 runs `41078356580` / `41078356597` 双绿，1356+；前面存在 1356 tests / 3 failures，再改断言后 success。不能直接据此说测试造假，也不能把改后绿灯说成真机通过。
3. **外部历史报告**：`F:/SourceReadSwift/reports/BUILD-118-设置层级与快速翻页彻底修复.md:6` 将“iPhone 13 Pro iOS 17.0.1 实机量测”写为测试环境；正文回溯的是 Build 117 用户现象，后文“100% 免疫”“彻底消除”没有附 118 真机步骤/视频/trace。此处仅确认报告存在这些声称，不采信为本次验证。
4. **产物证据（主审查已校验）**：桌面 118 IPA，12,648,654 bytes，SHA256 `1FEB3BCC878605E976C110E9FD20681C9338BEFE7534542411F5C047396D784D`，MinimumOS 16.0。存在且版本正确不证明体验正确。
5. **NOT RUN**：当前 HEAD 的 macOS 编译/XCTest、实时 CI run headSha 检索、iOS 16/17 真机读页矩阵、帧时间/内存峰值、Thread Sanitizer、Main Thread Checker。

## 4. 下一轮交接应先固定的输入与验收

- 固定一个有 hash 的本地 TXT/EPUB 与一个可缓存网络章节 fixture；先隔离书源延迟，再验证网络失败与补页。
- 稳定定位用 `(bookID, chapterID, paragraphID, UTF16Offset)`；显示页序号只是视口派生值，不能作为跨重排持久位置。
- 轨迹覆盖：连续前翻 100 页、反向 20 页、未完成拖动取消、跨章连翻、目录跳转、字号/字体/旋转、后台回来、退出重开、TTS 抢占、菜单/设置打开关闭。
- 断言无丢段/重复段/回跳；所有 accepted gesture 最多一次 commit；取消 gesture 零 commit；异步旧 generation 不覆盖新会话；页脚/最后行在真实 viewport 内。
- 记录 p50/p95/p99 帧时延、长帧次数、主线程 layout 时长、缓存命中、内存峰值、请求/重排次数。帧率数字不能代替视觉连续性。
- 新架构与当前架构通过同一 fixture/轨迹 A/B；先一条真实 renderer 闭环，再扩展全部模式，最后清理旧路径。

## 5. 本次输出与修改范围

仅新增本文与 `graph-project.json`；没有修改业务源码、测试断言、工作流、git 分支或用户设置。图为人工语义提取片段（Graphify schema），不是对全部 Swift AST 的完整图。节点/边均带来源与 EXTRACTED/INFERRED 标记。
