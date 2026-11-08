# build 132 · 阅读工坊与滚动连续性（CI 已通过，真机待验收）

## 最新修复 · 2026-11-03
- DELIVERED CI-PASSED TEST CANDIDATE84a43d6d35553fae970bbcfeebe00c416edd3576,1.1.7/build132: regular1255171876231605tests/2originalskips/0fail and native26125517186960182tests/0fail; unsigned125517187074success, both exact-head workflows41515294394/41515294404SUCCESS. Actually viewed7regular+7native route captures at320light/390bamboo+dark: no obvious overflow/wrong route/repeated old preview; themes images show loading only. Desktop C:/Users/Edc21/Desktop/SourceReadSwift-1.1.7-build132-84a43d6-unsigned.ipa,26802434bytes,SHA256f746d5b0da537106ffeb69dc7a2d8c62f80d93518fd28367da9ab8597c535e61. CRC/plist132/minOS16/arm64/iPhoneOS/fonts/ProMotion option/app+dSYM UUIDbaa45b65-bf61-3a0e-8fe1-d784b6210e74/postcopyhash passed. Old131 and463UNVERIFIED hash-preserved. ExactheadDELIVERY/IPA_VERIFICATION/IMPLEMENTATION_CHANGESET and repoATELIER-132-84a43d6-DELIVERY.json saved. No signing/install, userfont, gesture/interactive return, intermittent crash or120fps acceptance claimed; user13Pro retest required. Current dirty docs/backups retained. Monitor reason complete after successful delivery, not paused for failure; startup paused and12manual/no gateway unchanged.
- Latest candidate84a43d6d35553fae970bbcfeebe00c416edd3576 PUSHED:13605c5 repairs isolated JSContext report/clock boundaries (original cancellation assertions retained plus no-old-report check);757b6f5 changes ONLY pretest cold migration readiness budget180→600sec (observed completion187sec; product60sec timeout unchanged);84a43d6 catches create timeout inside same two-attempt boundary, never shuts down unknown IDs. Each policy change has RED→GREEN reproduction, all8 local tests/py_compile/Swiftsyntax/diff checks passed. Exact-head iOS41515294394(native125517186960/regular125517187623) and unsigned41515294404(job125517187074) now running. Old efe0 actual once-only native retry125508279831 completed PRETEST failure on BOTH cold migrations,101345byte log SHA256a9988f092cd7117c0b705920e400d45554c155b03a9fea386a826cfa9960c17b preserved; no third blind rerun. New push happened AFTER retry completed, not cancelled. Current application/test/script changes committed; previous dirty docs/backups preserved. New exactHEAD evidence CHANGESET/INFRA_RED_GREEN/FOLLOW_UP; no new Desktop delivery or native/FPS acceptance yet. Monitor ACTIVE, repair rather than auto-pause.
- efe0 full125499623618 completed1605tests/2originalskips/1failure: Release110RegressionTests.swift:38 isolated JSContext extracts jump functions without the newly used reportVisiblePosition/performance fixture dependencies (ReferenceError). BOTH real WebKit long-paragraph restore and held-rAF regressions PASSED; no >500/<=600 assertion changed. Added local VM reproduction RED, supplied explicit test-only report/clock boundaries, retained original cancellation assertions and added no-old-visible assertion; local2tests GREEN plusSwift syntax/diff check. Pending UNCOMMITTED paths: SourceReadSwiftTests/Release110RegressionTests.swift and scripts/test_reader_jump_reports.py. Native sameHEAD rerun actually requested HTTP201 at19:44:14Z, job125508279831; hold commit/push until retry completes so it is not cancelled again. Then commit/push isolated fixture repair, plus evidence-driven bootstrap fix if retry repeats. Do not mistake mirror regular job125508281715 for a rerun.
- efe0 native125499624142 PRETEST failure: bootstatus remains in LaunchServices data migration, first boot180sec timeout, cleanup30sec timeout, second simctl create30sec timeout outside retry boundary. GUI launch dependency is gone; not a product assertion or proof reader fix failed. Original63003byte log SHA256d7bc8e16a01ace2400e07365a0e00b2c566a90135aefe5b6ffad79d71e17cb2b and native boot artifact retained under exactHEAD/NATIVE_FAILURE_ATTEMPT1.json. SameHEAD reruns0; regular sibling still testing, wait for workflow completion then retry only failed native job once before lifecycle repair. Keep ACTIVE; no test skipped or timeout changed.
- 当前 efe0b9ebbbe1460efb54f53a45fe2f26ea09c543：跳转确认后立即提交真实位置，不依赖动画帧；手势滚动仍按120ms节流。保留原生字符位置断言，并增加暂停rAF的原生回归。Windows真实DOM复现先红后绿，旧跳转不能覆盖新跳转；不等于WebKit/真机通过。
- CI启动不再等待Simulator图形进程；simctl与180秒启动门槛未放宽。GUI挂起策略回归先红后绿，3项通过。按要求已对旧e477请求一次同HEAD重跑；新源码需新HEAD全量验证，旧重跑不冒充验证结果。
- 新CI41509738870/41509739061继续运行；已授权遇错修复重测，不自动暂停。

## 当前检查点 · 2026-11-03（覆盖下方历史候选状态）
- 当前源码 e4779318c5b2ab1580be6b251304ed3588cba5c8，包含测试桥接返回值及工坊重复预览修复；原断言和经典设置保留。
- 全量 XCTest 仍运行；native26 在应用测试前的 Simulator GUI 启动超时，同 HEAD job 重跑尚为 0 次，待同一 workflow 的全量任务结束后重跑一次，再按证据修基础设施。
- 同 HEAD 设备包已编译、下载并校验 CRC/plist/132/minOS16/arm64/字体/ProMotion 与匹配 dSYM UUID，最终验收未完成；桌面暂有旧463 UNVERIFIED测试包，131未覆盖。证据见准确 HEAD 的 IPA_CANDIDATE.json。
- 自动任务 ACTIVE：可修复失败继续修复和重测，不自动暂停，不跳测试，不将模拟器或截图当真机性能结果。

## 范围与设计决定
- 保留紧凑的真实最近阅读卡片，移除重复“继续阅读”按钮；整张卡片作为系统转场来源，按压不再先缩小书封。阅读恢复阶段显示同一本书的书衣与已存章节，不添加人为延迟。
- 设置从阅读现场底部升起，子页由同一个 NavigationStack 推入/返回；保留经典三栏设置开关。沿用 build 131 的非泛型延迟构建边界，禁止重新内联成巨大 View 值。
- 章首使用原创矢量章饰（素笺、藏书票、山岚、枝叶、星图），同一几何用于网页/原生分页/预览；独立标题字阶、字体、对齐。不替换真实书籍、正文、书源或阅读状态。
- 装帧仅捕获明确允许的外观参数：字体、纸张/壁纸原 JPEG 与裁切、章首、页眉页脚、菜单纸面。记录原子写入，字体缺失则整套拒绝；不保存账号、书源、书籍内容、位置或翻页模式。无新依赖。

## 已复现的滚动问题
- 基线 d3a9d8416c5bdfb768d81975e832c69dc057b87b，iOS run 41476122026 / regular job 125382032069：1591 tests，2 原有 skip，2 failures。
- 同一字体排版的 50 次位置更新，styleBuildCount 从 1 到 51（应保持 1）；真实字号变更后 52（应为 2）。原断言保留。
- 修法：原始排版输入与已解析 RGBA 颜色先比较，命中时不进入字体解析/CSS 构建；字体目录修订号使真实导入仍可失效重建。
- 章节追加保留原文前缀时，不调用 scrollTo(当前位置) 或终止滚动动画；仅替换/前插恢复锚点。字符范围几何查询收敛到已有报告节流点。滚动诊断只累加内存，离开/后台再落盘。

## 字体症状与边界
- 用户补充：QQ 保存到本地 Files 的约 12 MB TTF，点选后久等无结果。小于现有 64 MB 限制，不归因为超限或 iCloud。
- 原生 picker 的 asCopy 副本直接进入后台解析，不依赖 sheet.onDismiss，不再次进入提供方协调；LiveContainer 的宿主临时路径也按 picker 副本处理。20 秒等待上限、取消、失败保留原字体，迟到结果清理自有候选。
- 真实 TTF 补足到 12 MB 的本地导入回归在上述基线已通过；并不代表用户那份字体或真机已修好。将超时与迟到清理拆成确定性的独立用例，避免依赖工作线程在 40 ms 内启动。

## 验证检查点
- 本地 33 个改动/新增 Swift 文件 tree-sitter 解析无错误；project/workflow YAML 解析、node --check 网页脚本、git diff --check 通过。Windows 无 Xcode，尚未 SDK 编译。
- 基线 native26 job 125382031481 在测试前模拟器 bootstatus 180 秒超时，不算产品失败/通过。候选为 CI 新建干净模拟器，最多换一台重试一次，保留原超时门槛与失败证据。
- 候选新增：惯性追加/样式缓存、无滚动周期写盘、取消/超时字体、装帧重启/JPEG/缺字体/分页字符守恒、7 个真实设置路由静态挂载与窄屏/明暗截图。完整旧测试不跳过。
- e0fc8a4 初次 CI 已通过 regular 产品编译并进入 XCTest；后续补充整套装帧跨会话 apply 回归、实际壁纸明暗/填充状态捕获、冷启动已安装字体后台恢复、无障碍单列与面板底部对齐。必须以最终 HEAD 重跑，不复用旧头通过结论。
- 模拟器启动脚本的本地标准库单测 2/2 通过：一次超时只换一台新设备、两次失败明确失败；每次仍为 180 秒且不关其他设备。不是 macOS 实机运行结果。
- 下一步：提交候选、原生双运行时 CI、检查真实截图、打包校验并下载桌面；不能提前报告测试绿、修复闪退、手势流畅或 120fps。

## 仍需真机验收
1. iPhone 13 Pro / 用户报告 iOS 27.0.1：同一份 QQ 本地 TTF 点选→导入→应用→重启，取消与失败保留。
2. 长章节连续滑动/预取追加→点菜单→开关工坊/经典→二级返回；阅读位置守恒，复验 build 130 的间歇栈溢出。
3. 正在阅读/书架/详情/阅读的系统转场、中断与交互式返回；经典/减少动态效果路径。
4. 真机 Animation Hitches/Time Profiler、60/120 Hz 帧时间；视频帧率、模拟器截图均不能替代。

## 回退
用户可在工坊切换经典设置；首页原经典紧凑方案保留。源码按对应 feature commit 执行 git revert，不 reset，不删除原有修改。最后已验证桌面 IPA 仍为 build 131 / 4a5d62d，保持不覆盖。

启动页实验暂停；12 用户手测，不调用网关。原 dirty 文档/备份保留。

## 最终候选 CI 检查 · 2026-11-03
- HEAD463647d590a8667acdbcbf35b8f2ec98c57d8b58 的 regular125412915494：1604 tests，2 原有 skip，1 unexpected failure。唯一失败位于 ReaderScrollCadenceTests.swift:28，安装 scrollTo spy 的 JavaScript 表达式返回 Function，WKWebView 报 WKErrorDomain5 unsupported result type；尚未执行追加/前插断言，不能据此宣称惯性回归通过。
- 位置更新排版缓存回归、字体5项、装帧6项、设置工坊4项与旧设置栈3项通过。截图已产生但未做最终视觉验收。native26仍为测试前启动超时，无实际重跑。
- 原始日志及 SHA 在精确HEAD的 FAILURE.json；heartbeat build132-ci-ipa 已 PAUSED。本次只更新证据和文档，不改源码、不提交、不复制新IPA到桌面。旧131保留。后续修测试脚本返回值时保留所有断言，不跳过用例，再重跑双运行时与视觉检查。
