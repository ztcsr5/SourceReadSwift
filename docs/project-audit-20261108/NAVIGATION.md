# 导航与详情审查 · 2026-11-08

本轮处理用户第 1、5、8 项。工作区已有的历史修改全部保留；本文件只记录本轮增量，不把历史测试视为当前通过。

## 已确认的问题与修改

| 项目 | 决定性证据 | 本轮修改 | 验收状态 |
|---|---|---|---|
| P1 双套底部导航 | `RootTabView.usesNativeTabs` 固定返回 false，外层因此绘制自定义栏；iOS 26 分支同时创建原生栏，`RootTabChromeVisibilityModifier` 在首页又请求 visible。两套真实栏同时存在，与截图吻合。 | 所有系统共用保留各页导航栈的同一个 TabView，系统 TabBar 永久隐藏；自定义栏仍由阅读器 owner 控制显示，音频小播放器只保留一份。 | 代码根因确认；补充原生测试，待同 SHA iOS 18/26 运行与实图。 |
| P2 完整简介被短详情覆盖 | `detailCard` 原传 `displayBook.intro` 为 fallback，但 displayBook 已优先取 detail.intro，因此所谓 fallback 是同一份短详情；刷新还会将短详情保存回书架。 | fallback 改传原 book.intro；比较清理后的两份简介保留更完整者，更新书架时同样保留完整内容。移除与长按选词竞争的正文点击手势，使用独立 44 pt 展开/收起按钮并增加无障碍标识。 | 短详情、长 fallback、空 HTML、段落及尾字符原生回归已添加，未原生运行。 |
| P2 详情冷目录阻塞主线程 | `BookDetailView.load` 调用同步 `BookTOCacheStore.entry`，其内部使用 writer.sync 等待 IO 并同步 JSON 解码。 | 复用现有异步 `entryForReader`，添加 book ID 和 load generation 校验，避免切源过程中旧缓存覆盖新书。 | 源码路径确认；尚无设备时长量化。 |
| P2 详情离页后后台请求继续 | 缓存命中后的刷新与续页使用独立 Task，SwiftUI 页面任务取消不能取消它们；完成时仍更新书架，导致全局状态发布。 | 缓存刷新与续页在页面任务内 await；页面离开自动取消，返回后可恢复未完成的续页。保留代际校验。 | 添加真实 NavigationStack 挂载→启动两个受控请求→pop→两请求取消的回归，待原生运行。 |

## 第 8 项的边界

用户描述的是“书架→详情→侧滑首页”，不是阅读器退出。本轮没有用阅读器退出测试冒充该场景，也没有修改阅读器手势或关闭原生可取消转场。

没有可用的当前真机 Instruments 证据，不能证明用户看到的约 3 秒停顿全部来自冷目录 IO 或后台刷新。尤其本地示例书不会走远端目录缓存，因此上述两项不能解释所有本地详情返回案例。iOS 26 双栏同时布局、大标题恢复与原生 zoom 的交互仍需用本轮同 SHA 的首次长侧滑录屏核验。

新增 `testFirstDetailEdgeReturnRestoresInteractiveHomeAndOnlyOneTabBar`：不先做短拖预热，直接首次长侧滑，要求 1 秒内书架入口可点、自定义导航可用、没有可点系统 TabBar，再立即打开全局搜索。XCTest 自身有等待应用空闲的同步行为，因此它是功能/响应回归，不替代设备帧时测量；失败不得延长等待冒充修复。

## 仍存在的不足

- 简介若远端搜索与详情均已截断，客户端无法凭空恢复；应检查具体书源简介规则和原始响应。本轮保留已取得的完整文本，不声称修复所有源的上游截断。
- 简介 HTML 清理仍是正则与实体替换；复杂嵌套 HTML、script/style、字面尖括号等应统一到经过测试的文本提取边界，避免解析层与界面重复清理。
- 目录刷新中 `isComplete` 根据是否首屏推导，而不是明确的分页终止信号；对超出页数预算的目录不应无证据宣称完整。该项属于源目录管线专项，未在此跨模块修改。
- 详情有手动刷新按钮启动的独立 Task；本轮主要修复自动缓存刷新/续页生命周期。后续应统一所有刷新入口的任务所有权，而不是每个按钮各开任务。
- 原生栏隐藏回归需要同时覆盖 iOS 16/18/26、各 Tab 下的子页与阅读返回；本轮原生单测使用 iOS 26 的 `isTabBarHidden` API，旧系统由真实 UI 场景补充。

## 验证记录

已执行：

```powershell
python -B -X utf8 -m unittest discover -s scripts -p 'test_home_presentation.py'
python -B -X utf8 -m unittest discover -s scripts -p 'test_product_quality_scope.py'
git diff --check
python -B -X utf8 scripts/audit_current_swift_syntax.py HEAD
```

结果：首页现有 4 项 Python 回归通过；diff 无空白错误。Swift tree-sitter 比较检查了 184 个文件，本轮导航/详情文件无新增语法错误；全仓返回失败是 `SourceRateLimiterTests.swift` 的 4 项诊断（交主任务处理）。这些检查不等于 Xcode 编译或原生 UI 通过。

已将 `test_product_quality_scope.py` 的旧原生栏不缩小契约更新为“只有一个 TabView、三个根页面永久隐藏系统栏、保留自定义栏 reader owner 控制”，保留导航栈及非阅读页常驻断言，未删除测试。该文件 21 项回归通过。本轮文件限定的 `git diff --check` 通过。

需要纳入原生运行的 suite：

- `SourceReadSwiftTests/TabChromeRegressionTests`：只绘制一个导航栏，阅读 owner 释放不复活系统栏。
- `SourceReadSwiftTests/Release117DetailTests`：新增简介与真实详情 pop 取消回归，保留原 320/390 宽度截图测试。
- `SourceReadSwiftUITests/FloatingReadingDeskUITests/testFirstDetailEdgeReturnRestoresInteractiveHomeAndOnlyOneTabBar`：新增首次详情长侧滑与立即搜索。
- 保留原 `testShelfCoverReturnsToItsSlotAfterCancelledAndCompletedEdgeGestures`、详情保留 Tab 路由和阅读器返回所属详情等流程。

## 文件与回滚

本轮编辑：`SourceReadSwift/App/RootTabView.swift`、`SourceReadSwift/Features/Discover/BookDetailSummary.swift`、`SourceReadSwift/Features/Discover/BookDetailView.swift`、`SourceReadSwiftTests/TabChromeRegressionTests.swift`、`SourceReadSwiftTests/Release117DetailTests.swift`、`SourceReadSwiftUITests/FloatingReadingDeskUITests.swift`、`scripts/test_product_quality_scope.py` 及本报告。

本子任务未提交、未推送。共享工作区混有此前改动，禁止整文件 checkout/reset；由主任务在本轮独立提交后 `git revert <本轮导航修复提交>`，或按本轮 hunk 逆向应用。
