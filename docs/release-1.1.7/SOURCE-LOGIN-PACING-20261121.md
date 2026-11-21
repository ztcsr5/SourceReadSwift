# 聚合书源登录、请求控制与魔丸分类修复接续

日期：2026-11-21。仓库：`D:/Gemini反重力/SourceReadSwift2`。

## 当前检查点

- 分支：`唯一主线`。基线 HEAD：`34bdd05954fccaecde3e4a39892ee35df7307702`，父提交 `40fdae9da6a293fb2c791a9a51943367f34afa5e`。
- 本次发布配置为 **1.1.10 / Build 154**。用户已明确授权将本轮相关修复提交并推送「唯一主线」，运行原生测试及构建 IPA。最终提交与构建结论必须关联此次真实 SHA，不以本文的本机检查代替原生证据。
- 用户安装包仅据反馈推测为 1.1.9 / 153 / 40fdae；尚未核实安装包二进制身份。不能把用户手机当前行为当作本工作区修复后的行为。
- 用户反馈：syiism 缺登录入口；听雪注册打不开；登录结果不清楚；魔丸搜索无结果、分类 0、书籍加载失败；大灰狼和光遇任意书出现访问过快及等待提示，而参考 Yuedu 无此问题。
- 目标仍未全部完成：客户端修复已落地；原生编译、XCTest、真机交互及魔丸线上搜索 404 尚未验收。

## 已落地的修改及证据边界

### 登录入口与反馈

主要文件位于 `SourceReadSwift/Features/SourceManager/`，以及 `Core/Rules/SourceLoginBrowserAction.swift`、`Core/Rules/RuleExecutionContext.swift`、`Core/Engine/SourceEngine.swift` 与 `Core/JavaScript/JSCoreRuntime.swift`。

- 详情页增加“账号、登录与注册”入口，使用书源作者定义的表单与动作。
- syiism 展示 API Key / 网关配置及作者面板入口；没有编造不存在的账号密码 API。
- 显示作者脚本 toast、明确验证结果及“验证登录状态”操作。Cookie 存在只表示“已存会话”，不等于登录成功；源没有校验规则时明确标为尚未验证。
- 作者提示有界保存：最多 8 条，每条 1024 字符，过滤空白及连续重复消息。
- 动态配置保存调用作者 `login()`；静态 inline 登录避免再运行一次认证。
- 听雪保留 `/spa/#/register` fragment；注册浏览器显示地址、重载与 HTTP 错误，错误状态不假完成。
- 嵌套浏览器弹出时，父 sheet 的消失不会错误取消正在等待的脚本。

新增测试：`SourceLoginFeedbackTests.swift`、`SourceLoginRegistrationTests.swift`；扩展动态登录测试。实际账号、注册及真机 UI 尚未验证。九源没有可直接采用的有效 loginCheckJs，客户端不能据此承诺登录成功。

### 设备身份与缓存兼容

主要文件：`Core/JavaScript/SourceDeviceIdentity.swift`、`JSCoreRuntime.swift` 与 `SourceLoginCacheCompatibilityTests.swift`。

- 移除所有设备共用的 `java.androidId()` 固定值。当前 ID 来自捕获的 vendor identifier，经 SHA-256 取前 8 字节形成 16 位小写 hex；vendor ID 不可用时使用本机持久化 UUID。
- 兼容旧固定 ID 加密的本地登录缓存；保留 256 KiB 限制、JSON 对象校验、后来手填字段与已有 Cookie。旧固定值仅用于旧缓存解密。
- 共享设备 ID 是确定的客户端缺陷，但尚无线上证据证明它就是此次服务器封禁的直接原因。身份变化后部分源可能需要重新登录或重新登记。

### 请求、正文、阅读器、下载和导出

主要文件覆盖 `Core/Network/SourceRequest.swift`、`Core/Engine/SourceEngine.swift`、`Core/Rules/SourceDiagnosticClassifier.swift`、`SourceChapterNotice.swift`、`ContentParser.swift`、`Core/Storage/` 以及 Reader 与 BookDetail 调用方。

- 每次实际 transport retry 独立领取并释放源级限流许可。
- 删除收到短限流页后清 Cookie 并立即重发的客户端路径。
- 明确认证、封禁、人机验证、HTTP 429、源需更新时，不再自动重试或转 WebView 重放。保留 HTTP 403 的既有浏览器挑战流程。
- 短的 HTTP 200 限流正文识别为失败，保留原提示，不作为小说章节写入缓存；旧缓存中的匹配 notice 也过滤。
- 正文和目录续页遇源级阻断，向上返回失败，避免伪装成部分成功；普通续页超时、404 保留原有部分结果语义。
- 阅读器遇源级阻断停止补章与重试定时器，保留原因和手动重试；已被前台接管的任务不被后台误取消。
- 文本、漫画离线下载及导出遇源级阻断后暂停，不再补入更多章；保留已完成缓存，取消或未请求章不误标失败。图片 404 仍按普通单图失败处理。
- 限流提示用例是合成文本，尚未获得用户线上完整原文；不能宣称穷尽全部服务器文案，也不能保证服务端不再限流。

新增测试：`SourceContentPaginationFailureTests.swift`、`ChapterDownloadBlockingTests.swift`、`ChapterFetchBlockingTests.swift`；扩展 transport、rate limiter、parser、cache、Reader 和导出并发测试。

### 魔丸分类为 0：已定位的确定性缺陷

主要文件：`Core/JavaScript/LegadoNativeBridges.swift`、`JSCoreRuntime.swift`、`Core/Rules/SourceExploreMenu.swift`、`ExploreCategoryParser.swift`、`Features/Discover/ExploreSourceControls.swift` 与 `ExploreViewModel.swift`。

原探索规则读取 `cache.get(dateT)`，拼上 `"1"` 后解析。旧宿主在未命中时返回 `""`，解析得到真值数字 `1`，使原规则跳过分类请求并提示先登录。修复为未命中返回 JS `null`，真实缓存空串仍为 `""`，memory 中的 0 / false 保真；删除接口返回语义不变。

同时支持原探索规则的 `type=select` / `chars` / action 平台选择器；没有分类时保留作者返回的状态提示。未修改原用户书源 JSON 或添加魔丸域名特判。

Node 严格离线回放使用完整原库、原探索规则与当前 cache shim，所有网络由合成响应桩提供：

| 缓存未命中值 | 初始 tabs 请求 | 合成分类数 | 结果 |
| --- | ---: | ---: | --- |
| `""` | 0 | 0 | 原规则跳过请求，提示先登录 |
| `null` | 1 | 1 | 原规则正常执行 tabs 请求 |

另验证平台切换：切到无分类平台保留提示，再切回可以恢复分类；6 项 cache contract 检查均为 true。证据：`.evidence/mowan-cache-null-20261121/offline-replay.json`。**这不是 Swift、JavaScriptCore 或 iOS 实跑结果。**

独立只读复核合并原九源与三份作者更新，检查 20 个字面缓存读取及 1 个删除调用，未发现确定不兼容。另从当前 JSCoreRuntime 提取缓存段，在 Node 的 native JSON wire 模拟下 16 项检查通过；没有运行听雪和书山的动态编码脚本，不据此作全路径保证。

新增、扩展原生用例位于 `MowanSourcePipelineTests.swift`、`SourceScriptCacheTests.swift`、`SourceLoginCacheCompatibilityTests.swift` 与 `Fixtures/private-bank/mowan-source-pipeline.json`，包含匿名四阶段与探索菜单。

### 魔丸搜索与书籍失败：仍未闭环

- 两种 cache miss 下，原搜索均生成 `/api/search?keyword=fixture&page=1&page_size=20`；搜索不依赖这次修复的分类缓存。不能将分类修复当成搜索 404 已解决。
- 只读复核表明，新版九源交付物中的魔丸与原九源逐字段一致；fixture 保留完整阶段规则、只替换库的 origin，并对请求地址严格匹配。实际 loader 从 request.url 构建 URLRequest，未找到必然引起 404 的拼接差异。历史 docs 中有旧魔丸规则，但无生产引用，不能据此认定手机导入了旧源。
- 上述交付物位置：`D:/CMoved/Documents_IOS/source-compatibility-review/nine-source-client-delivery-20261120/nine-aggregate-updated-candidate.json`；文件 SHA-256 为 `55215cbb4c865dd016e97ed91719478b2abf2dd12304f4a0676b8e38c60754a7`。其中魔丸 canonical SHA-256 为 `f7e3a7a9f3100ba8d1c606fe4f9c73ad49fc272f71b3da5258ec4808dc807a00`。这些是外部输入指纹，不证明手机导入状态。
- 本机此前有限次直连采样可取得搜索 HTTP 200 / code 0；这只能说明当时本机路由可达，不能证明用户手机使用了相同源版本、参数、请求头或最终 URL。没有继续刷线上。
- 旧 App Web 端口此前使用明确无代理的直连仍超时，本轮没有反复连接、清空或重新导入用户设备上的源。
- 下一份决定性证据应来自同一候选包：安装版本与提交标识、脱敏后的魔丸源版本指纹、搜索实际 URL / method / 状态码，以及首个失败阶段。复用项目现有诊断入口，不索取密码、Token 或完整 Cookie。

## 本轮已实际运行的检查

在 Windows / Python 环境执行以下命令，合计 **48 项通过**：

```powershell
Set-Location -LiteralPath 'D:\Gemini反重力\SourceReadSwift2'
python -B -X utf8 -m unittest discover -s scripts -p 'test_source*.py' -q
python -B -X utf8 -m unittest discover -s scripts -p 'test_aggregate_source_config.py' -q
python -B -X utf8 -m unittest discover -s scripts -p 'test_release119_quality.py' -q
python -B -X utf8 -m unittest discover -s scripts -p 'test_bookshan_original_replay.py' -q
git diff --check
```

结果分别为 28、4、14、2 项 OK；`git diff --check` 通过。

发布配置更新为 1.1.10 / 154 后，上述 48 项重新运行通过；另外运行 `python -B -X utf8 -m unittest discover -s scripts -p 'test_reader_controls_workflow.py' -q`，16 项通过，发布前本机相关检查共 64 项通过。保留 `test_release119_quality.py` 文件路径以兼容既有命令，内部版本断言已更新为当前 1.1.10 / 154。

内联只读 Tree-sitter 对当前所有 tracked 变更及源目录新增 Swift，与 HEAD 对比：**50 个变更 Swift 文件，新增加的语法诊断 0**。此集合包含原有未提交的 fixture pipeline 测试，不能把全部差异都归为本轮。没有调用会覆盖已有 `CURRENT-SYNTAX.json` 的 audit 脚本。

提取变更文件的 XCTestCase class，核对 `source-rows-probe.yml`：22 个变更涉及的 suite，missing=[]。CI 已纳入新增分页失败、登录反馈、Reader、下载、导出与速率回归；测试目录由 `project.yml` 整体收录。

**未运行**：Swift 类型检查、Xcode build、XCTest、此次修改的 GitHub workflow、真机登录/注册/阅读及线上魔丸全流程。Windows 未安装 Swift、Xcode 或 gh；Node/Python/Tree-sitter 不能代替这些证据。原生验收命令以 `.github/workflows/source-rows-probe.yml` 为准，必须运行在包含本轮差异的同一候选 SHA。

## 保护范围、发布与回滚

- 原有未提交项 `SourceReadSwiftTests/SourceEngineFixturePipelineTests.swift`、`docs/project-audit-20261106/CURRENT-SYNTAX.json`、`docs/release-1.1.7/QUALITY-137-STATUS.md` 及无关 untracked 内容必须保留；本轮未覆盖这些文件。
- 不整体暂存、不清理工作区、不删除 worktree、不新造候选分支。仓库仍以 `唯一主线` 接续。
- 发布版本递增为 1.1.10 / 154，已带版本的工作流展示名同步；不以旧 SHA 的 CI 结果证明当前差异通过。原生结果以同一提交的 Source parser and corpus probes / iOS / Unsigned IPA 工作流为准。
- 原生测试的提交依赖已独立核查：不纳入原有 Tomato 测试方法与对应三份未跟踪 fixture；保留 HEAD 已跟踪的 Tomato fixture。本轮新的外部测试资源只有已纳入的魔丸 fixture，无需加入未跟踪私有语料或旧研究文档。
- 发布后回滚应使用针对本次发布提交的 revert，保留主线历史。提交前撤销时，仅逆向应用本轮局部 diff；共享的 JSCoreRuntime、SourceEngine 和登录缓存测试含多个相关修复，不能整文件还原，更不能执行整个工作区的 reset/clean。

本文件独立记录本轮状态，避免覆盖接手前已有改动的 `QUALITY-137-STATUS.md`。

## 1.1.10 发布后的原生回归修正

- 发布提交：`3e61bf058c50e6f85c5735f1f86cd1e16a8f8fe4`。对应 Source parser and corpus probes #52（run `44839135699`）编译成功；离线解析执行 1154 项测试，有 2 个断言失败，均来自 `SourceLoginRegistrationTests.testRegistrationKeepsAuthoredHashRouteAndWaitsForBrowserResult`。后续语料探测 5 项通过，目录语料 97 项 mismatch 为 0。这些结果不等于整条工作流通过。
- 同一发布提交的 Unsigned IPA #859（run `44839135690`）已成功；iOS 完整验证 #888 在本次修正前仍在运行，未计为通过。
- 根因是新增测试违反既有浏览器返回值约定：`java.startBrowserAwait(url, title)` 在浏览器完成后重新请求原始 URL，第三参数为 `false` 时才直接返回浏览器页面。旧测试既没有注入离线网络，又期待直接返回浏览器最终地址，导致 `.invalid` 域名请求失败及 `about:blank`；另一个失败是 Darwin `URL.path` 对末尾斜杠的表示与测试预期不同。
- 修正仅涉及此测试：保留作者的两参数调用，注入独立网络夹具，严格核对完整 hash URL、浏览器写入 Cookie 后仅一次重取请求，以及网络返回的最终 URL、原始 URL、正文和状态。浏览器正文与重取正文刻意不同，以防错误返回浏览器 DOM 也通过测试。未放宽断言、跳过测试、延长超时或修改生产代码。
- App 版本继续为 **1.1.10 / Build 154**，此测试修正无需重装。新提交的原生结果须以其实际 SHA 关联的重跑为准；Windows 语法检查不能替代 XCTest。
- 原始失败日志保存在 `.evidence/release1110-ci/source-probe-136642872590.log`，SHA-256 为 `5cffdc8427da9b69f6cc3d29f5d22c3e3fdf8007accda8b0338a6355704d88b5`；两个断言位于日志 15952–15953 行。
