# Antigravity 书源离线回归修复记录 · 2026-11-26

基线为 `c06280263b722e3b670b3afd4b7bd902f21b2be4`。本次只处理该 SHA 的原生 CI 已暴露的书源回归，没有重新在线检测全部书源，也没有修改失败断言以掩盖问题。Windows 本地检查不能代替 iOS SDK 编译或原生 XCTest。

## 基线证据

原始日志、job 元数据、去重失败记录位于 `output/antigravity-release-20261126/baseline-ci/`。日志体积与 SHA-256 见该目录的 `manifest.json`，避免在文档复制数 MB 日志。

| 现象 | 可复查位置 | 根因与修复 |
|---|---|---|
| 脚本目录得到 `[第二话, 第三话, 第一话]`，期望 `[第一话, 第二话, 第三话]` | `build-job-139087641199.log:12711`；`parser-job-139087638276.log:13759`；`ChapterListMetadataTests.testScriptedHTMLCatalogKeepsOriginalLinksAndAddedRowsInOrder` | `selectionValue` 在脚本追加章节前执行 `-` 逆序；改为整个选择流水线完成后逆序一次，保留 HTML 节点和混合数组。 |
| `.bookList[*]` 把根部 1 项与嵌套 2 项合并成 3 项 | `build-job-139087641199.log:14105`；`JSONListDescendantTests.testDirectListPathWinsOverDescendantScan` | 普通列表规则先尝试显式根路径，缺失时保留 descendant 兼容路径；带脚本或模板的规则仍单次执行原流水线。 |
| 漫画传输启动数超过 4 | `parser-job-139087638276-failures.json`；`RemoteComicImageTests.testComicTransfersStayBoundedAndCancelledWaitersDoNotStart` 与 `testRepeatedChapterCancellationReleasesAllFourPermitsForTheNextChapter` | `ComicImageBudget` 默认值为 8，原有原生契约要求 4；恢复默认值 4，显式 `limit: 1/2` 调用不变。 |
| 响应 `loginCheckJs` 未执行，401 先行失败，取消后仍解析 | `build-job-139087641199.log:19181` 起；`SourceResponseLoginCheckTests` | 五个阶段首载需要响应 hook，在 HTTP 状态拒绝前运行；分页和 hook 内重发不递归执行。 |

`ComicImageCookieBoundaryTests.testAnonymousEngineAndLoggedOutEngineDoNotReceiveAmbientCookies` 在 parser job 的第二次 anonymous.png 请求出现一次 `-1001`；同一 SHA 的 build job 该用例通过。现有证据只证明一次超时，未证明 Cookie 泄漏或固定产品缺陷，因此未改 Cookie 产品逻辑或测试断言。

## 固定改动范围

- `SourceReadSwift/Core/Rules/JSONRuleExtractor.swift`：脚本完成后逆序；普通 leading-dot 列表优先根部匹配；空数组 `[*]` 保持空选择，防止误回退到不相关嵌套列表。普通 `value(.data.content)` 与脚本列表输入继续保留原有 descendant 形状。
- `SourceReadSwiftTests/JSONListDescendantTests.swift`：新增根部空列表不回退到嵌套列表的原生回归。
- `SourceReadSwiftTests/JSONRuleExtractorTests.swift`：新增 `@js:` 与 `<js>` 两种标记在脚本追加章节后再逆序的原生回归。原有根部优先、descendant 兼容、脚本单次执行与 HTML 目录测试均保留。
- `SourceReadSwift/Shared/DesignSystem/ComicImageBudget.swift`：默认并发恢复为 4。
- `SourceReadSwift/Core/Engine/SourceResponseLoginCheck.swift`：新增响应 hook 适配器。只在 hook 内提供 callable `code()` 与 `java.getStrResponse(null, null)` 原请求重发，结束时恢复原函数；保留原响应，或读取返回 `StrResponse` 的正文、URL、状态与头。重发最多 8 次，预算或传输失败即使被脚本 catch 也返回阶段失败。
- `SourceReadSwift/Core/Engine/SourceEngine.swift`：搜索、发现、详情、目录、正文五个首载阶段在 HTTP 状态拒绝前执行一次 hook；后续分页和 hook 内重发不递归调用。原响应先写入 Cookie 持久状态，hook 返回后写入最终响应；WebView 判断使用最终响应。
- `SourceReadSwift/Core/Network/SynchronousSourceNetworkBridge.swift`：新增具体 `SourceRequest` 重载，重发保留 method、body、headers 与请求选项，实际发出前解析当前自动 Cookie。复用既有 `SourceLoginCancellation` token，跨同步 JS、GCD 和 detached 网络任务检查取消。
- `SourceReadSwiftTests/SourceResponseLoginCheckTests.swift`：保留原有 8 个测试，将五阶段替换 fixture 加强为 `Unchanged → Checked`；新增重发中取消、脚本 catch 后预算仍失败、布尔 completion 保留原响应 3 个测试。
- `scripts/test_source_response_login_check.py`：新增 5 项离线 Node 回放，提取生产适配器与既有 JS runtime 桥，验证响应字段、正文替换、null/null 重发、委托与恢复、异常与非响应 completion。
- 本文记录证据、检查边界与原生验收命令。

共 10 个文件。既有 `SourceReadSwift/Core/Verification/SourceBrowserLoginCoordinator.swift`（定义 `SourceLoginCancellation`）与 `JSCoreRuntime.swift` 未修改。这些改动影响 JSON 书源列表、脚本目录、响应登录 hook 和默认漫画图片传输并发，不改变书源格式或持久化字段，无需数据迁移。

## 已执行的本地验证

环境为 Windows PowerShell，`swift`、`swiftc`、`xcodebuild` 均不可用。以下脚本离线执行，不访问生产书源：

```powershell
python -B -X utf8 -m unittest discover -s scripts -p test_source_transport_boundary.py -v
python -B -X utf8 -m unittest discover -s scripts -p test_comic_transport_boundary.py -v
python -B -X utf8 -m unittest discover -s scripts -p test_source_bridge_installers.py -v
python -B -X utf8 -m unittest discover -s scripts -p test_source_response_login_check.py -v
python -B -X utf8 -m unittest discover -s scripts -p test_source_android_bridges.py -v
```

结果分别为 10、3、1、5、4 项通过，共 23 项。八个 Swift 改动文件的 Tree-sitter Swift 语法诊断均为 0，相关代码的 `git diff --check` 通过。机器可读证据见 `json-comic-fix-checks.json`、`json-fix-syntax.json`、`comic-budget-fix-checks.json`、`response-login-hook-checks.json`。响应 hook 的 Swift 部分仍需原生 CI 类型检查与执行；Node 回放只证明实际生产 JavaScript 桥的离线行为。

## macOS CI 原生验收

原生验证尚未在当前 Windows 工作区运行。以下命令需在安装 Xcode 与 XcodeGen 的 macOS 上执行；`<SIMULATOR_ID>` 为实际可用设备 ID。验收要求六个类全部通过，并复查 Cookie 超时是否重现：

```bash
xcodegen generate
xcodebuild -project SourceReadSwift.xcodeproj -scheme SourceReadSwift \
  -destination 'id=<SIMULATOR_ID>' CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:SourceReadSwiftTests/ChapterListMetadataTests \
  -only-testing:SourceReadSwiftTests/JSONListDescendantTests \
  -only-testing:SourceReadSwiftTests/JSONRuleExtractorTests \
  -only-testing:SourceReadSwiftTests/SourceResponseLoginCheckTests \
  -only-testing:SourceReadSwiftTests/RemoteComicImageTests \
  -only-testing:SourceReadSwiftTests/ComicImageCookieBoundaryTests test
```

## 回滚

初批修复已作为 `4498c2b6` 合入并推送唯一主线，主题提交为 `71b4891e`。追加修复的实际提交及整批回滚命令记录在最终包的交付收据中。不要使用整工作树 reset 或 restore，以免覆盖同时进行的主题与其他改动。

## 首次原生结果与普通校验响应回归

`4498c2b6` 的 source run `45683943612` 已完成应用与测试原生编译；1171 项离线原生测试只有 `SourceDynamicLoginTests.testFormLoginAndCheckUseTheInjectedTransportAndCurrentSession` 失败。日志见 `output/antigravity-release-20261126/current-source-ci/manifest.json` 与 `parser-test.log:2110`，总数见 `parser-test.log:3048`。目录元数据 28 项、JSONRuleExtractor 99 项、漫画图片 26 项通过，前述 Cookie 用例本轮也通过。这份 workflow 当时没有选中新的 `SourceResponseLoginCheckTests` 与 `JSONListDescendantTests`，不能把这两个类计为通过。

唯一失败的决定性输入是 `loginCheckJs: java.ajax('/verify')`。既有兼容桥把普通 ajax 结果包装为带 `body()`、数值 `code` 的对象；新增适配器只检查 `body()`，误把校验接口的 `true` 当作搜索替换正文。实际 `StrResponse`、首响应与 null/null 重发对象均提供 callable `code()`，因此追加修复仅接受这一响应形状，不修改共享 ajax API。

普通 ajax completion 的 Node 用例先复现失败，再由同一生产桥回放验证；Swift 加入对应的搜索行为回归。原登录用例增加真实书名断言，保留全部鉴权头和 Cookie 断言，请求序列明确包含搜索首响应 hook 产生的第二次 `/verify`。原生 workflow 补入遗漏的两个测试类。追加修复的原生与 IPA 状态以最终同 SHA 收据为准，不能沿用 `4498c2b6` 的编译结果。

追加修复的 Windows 检查：`python -B -X utf8 -m unittest discover -s scripts -p 'test_*.py'` 共运行 324 项，结果 OK（1 项条件跳过）；生产桥最终精简后再次定向回放 6 项全部通过。相对 `4498c2b6` 的 3 个 Swift 文件无新增语法诊断，`git diff --check` 通过。红绿日志和 `RESPONSE-CHECK-FINAL-SYNTAX.json` 为本地证据，不冒充原生结果。
