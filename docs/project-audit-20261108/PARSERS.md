# 解析、漫画传输与净化审查 · 2026-11-08

本批发现并修复了正文回退漏净化、段落合并、无效规则静默接收、规则保存失败仍显示成功、校验 JS 可逃逸执行、视频候选选错等问题。漫画超限测试已恢复真正的零正文条件；两次原生对照证明系统未在零正文时交付响应，现拆分为可见响应立即限额与不可见响应显式超时，候选仍待新 SHA 原生验证。旧 `e2f4c7ff` 双系统通过仅是接手基线。

## 改了什么

| 优先级 | 现象与决定性代码证据 | 修法与回归 |
|---|---|---|
| P1 | `ContentParser.extractFallbackParagraphs` 将 HTML 用 `SwiftSoup.text()` 合并成一行；`parseHTML` 的普通/异常回退均绕过 `applyContentTransforms`。因此行首正则在预览有效，实际自动提取正文仍残留广告。 | 保留段落与图片标记，回退提取后执行书源及全局净化。`ContentParserTests.testFallbackContentStillAppliesSourceAndGlobalPurification` 覆盖无规则/规则未命中；`testFallbackDoesNotResurrectTextRemovedByPurification` 防止清空后复活原广告。 |
| P1 | `RuleEditorValidator` 原来把用户脚本直接插入 `(function(){...})` 后执行所谓“语法检查”。脚本可关闭包装并执行外部语句。 | 先 JSON 编码脚本，再传入 `new Function(string)`，只编译不调用。净化校验复用同样方式。Node 独立实验已复现旧包装逃逸、新方式拒绝；原生 JSCore 回归仍待跑。 |
| P1 | `PurifyRuleStore` 在 `save` 前改内存；失败只设置 `lastError`，导入仍返回正数。界面无条件清输入并显示成功。 | 先持久化候选快照，成功才发布新规则；新增规则返回可忽略的 Bool；批量失败返回 0，界面保留文本与选择。真实临时目录中用同名目录阻断文件写入，覆盖新增/导入/停用/删除失败。 |
| P2 | 无效正则被保存为启用状态，执行器静默跳过；多行 JS 按行拆开成数条。 | 新建 `PurifyRuleValidator`；整批校验失败不做部分导入；多行 JS 保留为单条。旧无效规则保留可删除、显式提示且排除执行，不破坏备份。 |
| P2 | `PurifyRulesView.body` 每次输入或刷新时同步跑所有正则/JS，重复编译/执行可能阻塞界面。列表名“已启用规则”却包含停用规则。 | 改为显式运行预览，使用既有 `BlockingRuleExecutor.run` 的 libdispatch 队列，样本上限 10,000 字；列表更名“全部规则”，说明缓存重新加载时机。输入上限不是 JS/正则执行期限，不宣称已彻底解决恶意规则卡死。 |
| P2 | 内置水印正则的裸 `飘天文学`、`最新网址` 前缀会删除正常叙述；“作者附言”实际可删任意位置的原文，并非只删章节尾巴。 | 新预设要求明确首发/发布/网址提示，补正常叙述与真实提示对照；附言预设明确告知会删作者原文。已导入旧规则不静默改写。 |
| P2 | `VideoContentParser` 的 `url ?? playUrl` 遇到空/非法 `url` 就遮住后面的有效地址；全局 `source[src]` 会取到前置音频源。 | 逐候选解析并跳过无效值，HTML 限定 `video source[src]`；保留签名 query、协议相对地址与 HTML 实体回归。 |
| 验收真实性 | `HeldComicHTTPServer.declared` 实际发送 1 字节，但 `sentBodyBytes` 仍为 0；原“零正文提前拒绝”断言因此不能支持结论。单次 `send` 也不保证发送完整帧，却按整块累计。 | 恢复 `.declared` 零正文、不发 EOF；新增独立 `.declaredPrefix` 明确记 1 字节场景；循环处理 partial send/EINTR，仅累计真正发送的正文。停止仅 shutdown，worker 负责 close，避免 fd 重用与关闭竞态。 |
| P2 | `ComicImageReceiver` 无条件打印完整响应 URL、错误对象及每个 chunk，可能记录签名参数并增加日志成本。 | Release 不输出诊断；Debug 仅在 `SOURCE_READ_COMIC_DIAGNOSTICS=1` 时输出任务号、长度、状态码与错误码。 |

以下记录第一阶段保留原 `tooLarge`/4 秒断言的过程；取得两轮决定性证据后，第二阶段的契约纠正在后文说明。累计字节上限始终不变。零正文分支并行启动独立 Foundation `URLSession` 对照，失败时输出：服务端接收请求/发完整响应头/正文计数、原生 response 回调是否出现、`task.response` 是否存在、预期字节数与完成错误码。如果独立系统与生产同时未收到 response，需继续定位系统交付约束；如果原生对照已收到而生产未完成，继续查生产 continuation/调度。

### 原生失败收敛 · ff0f398

`ff0f398dd4f70793b93b491abc5ac10287700fa6` iOS 26 日志 `F:/SourceReadSwift/reader-quality-137/verification/ff0f398dd4f70793b93b491abc5ac10287700fa6/native-tab-test.log:1322`：两服务端均已发送完整 104 字节响应头，正文 0 字节、连接未结束；4 秒时独立 Foundation 显示 `responseCallback=false taskResponse=false expectedBytes=0 responseExpectedBytes=-1 errorCode=none`，生产同样无 response 回调。随后测试主动取消，才返回 `.cancelled`；不能说取消覆盖了 `.tooLarge`，因为生产尚未看到可判断长度的响应。

同次运行的 `declaredPrefix` 发送 1 个真实计数字节后立即交付头并返回 `.tooLarge`，chunked 达到累计上限也立即拒绝。生产取消后 metrics 出现 `responseStarted=true`，进一步说明网络栈内部开始收响应与向应用交付 response 是不同阶段。目前证据反驳“只有生产 continuation 出错”的解释；仍不足以单独证明 MIME sniff 是唯一根因。

新增独立诊断 `RemoteComicImageTests.testZeroBodyFoundationDeliveryWithSingleVariableResponseHeaders`，原验收方法保留不变：

1. 基线 `application/octet-stream`、仅改 `image/png`、仅加 `X-Content-Type-Options: nosniff`，逐个实验；每组同时跑独立 Foundation 与生产 RemoteImageLoader。
2. 同配置响应先只发头，等待至多 4 秒，日志记录两边 response/结果及服务端真 0 字节；不把缺少回调算通过产品验收。
3. 在同一连接显式释放 1 个已计数字节，不新建请求、不发 EOF。要求此后 1 秒内可见 response/`.tooLarge`，并观测两连接真正被客户端关闭。
4. 如果 MIME/nosniff 在 0 字节阶段改变交付，可支持对应内容识别假设；如果三个配置均只在释放字节后交付，支持公共 URLSession 的首字节前交付限制，不能凭空制造 `.tooLarge`。后续需分别验证“可见头立即限额”和“不可见响应超时/取消”，原 4 秒零正文失败保留到取得证据并明确产品契约为止。

本轮仅增加测量，不改生产限额、回调顺序或超时策略；不使用私有 CFNetwork 选项，不添加重复 HEAD 请求。诊断方法是否跑完与原验收是否通过分别记录。


### 交付限制与超时修复 · 6f9df48 之后

定向原生 `6f9df48d445a8b9e9011f846082616f992184716` 日志 `F:/SourceReadSwift/reader-quality-137/verification/6f9df48d445a8b9e9011f846082616f992184716/diagnostics/diagnostic-unit.log:352` 给出决定性结果：

| 单变量响应头 | 4 秒、0 字节时 | 同连接释放 1 字节后 |
|---|---|---|
| `application/octet-stream` | Foundation 和生产均无 response，task.response=nil | 约 12.22 ms 后双方 response；生产 `.tooLarge`，两连接关闭 |
| 仅改为 `image/png` | 双方无 response | 1 秒后仍无 response，原“一字节足以交付”假设被否定 |
| octet-stream 仅加 `nosniff` | 双方无 response | 约 11.88 ms 后双方 response；生产 `.tooLarge`，两连接关闭 |

这证明在已测 iOS 26 CFNetwork 公共接口上，系统内部收到 HTTP 头不等于应用可读取头。MIME 会改变需要多少正文才能交付，但 nosniff 没有绕过零正文等待。旧验收要求在没有 response/Content-Length/expected-length 可读时返回 `.tooLarge`，实际上要求应用知道系统未公开的信息；仅靠 URLSession 无法满足，不能凭等待时间伪造大小错误，也不应新增 HEAD 请求或自写 HTTP/TLS 以迎合用例。

同时发现真实配置缺陷：`RemoteImageLoader.fetchComicBytes` 给 URLRequest 显式写 18 秒，覆盖了注入 session 的更短 request timeout。修复位于 `ComicImageTransport.load`：有效请求等待取 URLRequest、URLSessionConfiguration request 与 resource 三者有限正值的最小值；非法非有限/非正配置回退已有默认。默认产品请求仍为 18 秒、资源总期限仍为 30 秒。使用系统原生 timeout 完成与现有 `.timedOut` 映射，不在没收到头时制造 `.tooLarge`，不修改累计 24 MiB 上限。

原测试场景仍覆盖，按实际可观测契约拆开、准确命名：

- `testDeliveredOversizedComicResponsesStopBeforeTheServerFinishes`：已交付的超限声明（真实 1 字节 prefix）和 chunked 累计超限都必须 4 秒内 `.tooLarge`，真实连接关闭、无服务端 EOF。直接 delegate 的零正文可见响应、超大 Content-Length、取消重入严格断言全部保留。
- `testZeroBodyResponsesHonorConfiguredTimeoutAndNeverEnterTheImageCache`：三个 MIME 变体均只发头、正文 0 字节、无 EOF，显式 request timeout=2 秒、resource timeout=30 秒，仍在原 4 秒预算内要求 `.timedOut`。同时检查不是立即网络失败（至少 1.5 秒）、真实连接关闭、图片缓存为空、订阅释放。没有跳过此场景，也不接受 `.cancelled` 代替 timeout。
- `testZeroBodyResponseHonorsAShorterPerRequestDeadline`：配置仍 18/30，单请求 2 秒，真实零正文连接须在 4 秒内 timeout 并关闭，防止反向把用户短请求放宽。
- `testComicTimeoutPolicyKeepsFiniteDefaultsAndTheShortestValidBound`：覆盖默认值、各个短期限及 0/负数/NaN/Infinity 边界。
- 原 MIME 对照诊断继续保留：PNG prefix 改为正常可解码的完整 3×2 fixture（83 字节；相对于声明的 24 MiB+1 HTTP 正文仍只是前缀，不发 EOF），明确记入正文计数，其余仍 1 字节；严格要求 prefix 后响应可见并拒绝/关连接。这是下一次可证伪实验，不把待执行结果写成通过。

本次行为变化是修复显式短超时配置失效，并在有证据后纠正不可观测长度的错误验收要求。没有放宽可见超限响应的拒绝条件，保留默认用户等待时长，没有删除、跳过或假造真实零正文验证。新候选 Windows 只能做语法与结构回归，2 秒期限及 PNG 完整小图前缀诊断仍需原生运行。

### PNG 前缀实验纠正 · 714cfbb 之后

`714cfbb0805b55605e823b6db34027f62cd9b57a` iOS 26 原生单元测试中，零正文三 MIME 的 2 秒 `.timedOut`、较短单请求期限、可见声明超限与 chunked 累计限额均已通过。当前日志 `F:/SourceReadSwift/reader-quality-137/verification/714cfbb0805b55605e823b6db34027f62cd9b57a/native-tab-test.log:1410` 显示剩余诊断失败：PNG 83 字节已完整发送，但独立 Foundation 仍 `responseCallback=false taskResponse=false`，生产 pending；两个 octet-stream 变体仍在 1 字节后立即响应。由此不能把“完整小图已发出”推导为“URLSession 必已交付声明超大的 HTTP response”。此前 83 字节后必交付的断言是假设错误，不是已证实的生产 continuation 故障。

本批只改诊断测试与本地 HTTP 夹具。保持同一 response 头、Content-Length、连接、无 EOF 条件，按累计正文 `[初始前缀, 256, 512, 1024, 4096, 16384, 65536]` 字节逐级推进。PNG 初始仍 83 字节，octet-stream 初始仍 1 字节；后续补零只用于网络交付测量，不宣称该超大响应是可解码图片。每级最多观察 0.5 秒，总前缀观察预算仍 4 秒，日志同时记录两路目标累计字节、实际 send 字节与 response/拒绝状态；已经交付的一路停止增加正文。最终停止写入但不关服务端连接，仍要求双方 response 已交付、生产 `.tooLarge`、实际客户端关闭。

这些分段值只是实验取样点，不是预设系统阈值；若 64 KiB/4 秒内仍不交付，用例继续失败，保留精确证据，不增加“未交付就取消也算通过”的路径。取消只清理已失败的请求。真实零正文超时与已可见响应的 4 秒限额回归完全不改。Windows 两个修改文件语法检查、传输结构回归、diff 检查通过，新的分段原生结果待主任务统一验证。

## 影响面与能力评价

### 小说与书源

目前有完整的搜索、详情、目录、正文主链，并支持 HTML/CSS、JSON 规则、JavaScript、相对地址、分页、Cookie、源变量、部分 Legado Java 桥接和 WebView 回退。`SourceEngine` 已把同步规则运行放入专用边界；新净化预览复用它，无新依赖。

能力上限仍需明确：

- `HaiKuoShiJieSourceAdapter.swift:111` 的详情、目录、正文规则仍全部为 nil，搜索/发现是字段映射，不是完整海阔运行时。显示“海阔导入成功”不能解释为可读全链成功。
- `XbsBookSourceAdapter.swift:165` 显式排除 video/comic/audio，只导入小说；需要在导入结果中明确“不支持的源类型”，不能把这类减少当成远端失效。
- `XPathRuleTranslator.swift:27` 拒绝 parent、ancestor、preceding 等无法翻译的轴；不是完整 XPath 引擎。`LegadoNativeBridges.swift:359` 的 un7z/unrar 明确不支持。
- 现有 `WebViewFallback` 通过 XHR/fetch 文本响应嗅探；不能据此声称已支持任意 WebSocket、blob/MSE、DRM 视频或跨域 iframe 全流量。
- 旧能力文档有过时项：本次确认 `ChapterListParser` 已有 inherited/trailing volume 传递，不再直接沿用旧“跨页续卷未处理”结论；`preUpdateJs` / `downloadUrls` 的完整执行仍未在这次抽查主链找到，不认定全量兼容。
- 本批未逐个重测所有公网书源。已有 corpus 单测和旧线上报告分别代表规则样本与当时网络状态，不能推导今天所有源可用。后续逐源应记录搜索→详情→目录→正文在哪一阶段失败，并区分失效规则、鉴权、验证码、限流与服务端故障。

### 漫画

`ComicContentParser` 已处理 HTML/图片包装、JSON 多层容器及转义字符串、请求头、相对地址、有序去重；保留 `nextContentUrl` 来区分完整与部分缓存。图片候选过滤媒体播放列表/HTML，扩展名为空的合法图片 API 仍允许尝试。传输按实际接收字节设限，离线有独立图片清单及验证。

仍不足：

- 规则解析不等于图片解码或完整章节验收。页面顺序、长图清晰度、过期签名、跨章/缩放/离线重启仍需要独立场景验证。
- JSON 回退容器有 6 层深度限制、固定字段表；不是任意站点协议解释器。标准规则可以抽取未知字段，自动回退不足不应强行猜错图片。
- 去重依据完整请求（URL+headers）。站点故意重复使用同一图片作为两个实际页时会折叠，这是当前策略边界，需要按真实源例子决定是否扩展显式页身份。
- 对系统尚未交付的零正文响应，不能判断服务器声明长度。当前候选以显式期限 `.timedOut`、真实连接关闭、0 字节与不缓存作为验证；对可见超限头和累计超限正文继续严格 `.tooLarge`。新候选须双系统原生验证，不用 prefix 通过替代零正文场景。

### 视频

当前适合直接 HLS/MP4 地址及规则已抽取的媒体 URL，支持有限 JSON 字段和 `<video>/<source>`。这与完整视频平台兼容仍有明显差距：

| 优先级 | 代码位置 | 确认的缺口与影响 |
|---|---|---|
| P1 | `VideoPlayerView.swift:525` | 每次换集启动无持有句柄的 Task，没有代际校验；旧请求迟到可把当前播放器换回旧集，退出后也可能继续 setupPlayer。应参考音频协调器的 loadID + task cancel。此批未改播放器结构。 |
| P1 | `VideoPlayerView.swift:551,643` | block 形式通知 observer 的 token 未保存、cleanup 未 remove；切集/反复打开会保留旧回调，生命周期不完整。 |
| P2 | `VideoPlayerView.swift:547` | 仅 `AVPlayerItem(url:)`，没有媒体请求上下文；依赖指定 Referer/UA/授权 Cookie 的流可能“解析到地址但不能播”。不能简单把源全部凭据转发到 CDN，需按实际资源域和公开 AVFoundation 能力设计。 |
| P2 | `ContentParser.swift:198,561` | 正文规则最终会剥 HTML 标签；视频源若返回播放器 HTML 而非具体 src，进入 `VideoContentParser` 前媒体标签可能已丢失。当前缺少真实媒体载荷模型和独立媒体规则通路。 |
| P2 | `VideoPlayerView.swift:573` | 播放进度把 `time.seconds` 直接转 Int；应防非有限值。状态处理、资源失效重取、MSE/blob/DRM/字幕/多清晰度不能由现有简单 URL 提取器代替。 |

这些缺口应优先修复；本批不使用未核验的私有 AVURLAsset 选项、不增加跨域凭据转发，也不把源规则的 `sourceRegex` 嗅探能力夸大成任意站点视频支持。

### 净化仍开放的边界

- 规则目前是全局 pattern/enabled，没有按书/源作用域、命中数、逐规则差异、撤销与顺序编辑；兼容 Legado 净化 JSON 时不能直接丢弃作用域而全局启用。
- URL 导入仍使用 `URLSession.shared.data` 整体接收，未在接收阶段限字节，也没有页面退出取消句柄；需增加有界导入传输。本次只收紧 HTTP(S) 地址并修正错误反馈，未假称解决内存边界。
- regex/JS 没有硬执行期限，复杂正则或死循环依然可能持续占线程；后台运行只消除界面刷新触发，不提供沙箱取消保证。
- 缓存含净化规则签名，改规则后重新请求会失配刷新；已经显示在阅读器内的正文不会因为规则变动立即重算。现界面已说明重新加载。
- 内置规则均为可选，没有默认自动启用。本次改保守预设不覆盖用户历史规则；已导入旧模式可先停用再删除/重导，避免无提示改变用户规则。

无需迁移数据、无新第三方依赖。旧规则与现有工作树全部保留。`add` 从 Void 改为带 `@discardableResult` 的 Bool，原有忽略返回值的调用仍兼容；UI 新调用按成功状态清空输入。

## 怎么验证

### 2026-11-08 定向原生补充

诊断提交 `bb483ffc0ecf817834837828a9d657f88804d8e8`、run `42410814438` 的漫画 20 项通过。分段实验中 PNG 的 83 / 256 字节前缀均未交付响应，512 字节时独立 Foundation 与生产传输均交付头部，生产返回 `tooLarge`；这只是该系统本次观测，不作为通用固定阈值。零正文三种 MIME 均约 2 秒超时，实际 socket 关闭且正文计数为零。旧用例严格的已交付响应/累计字节拒绝契约仍保留。

整轮诊断并未通过。结果包根记录明确记录 `Test exceeded execution time allowance of 1 minute`，归属 `HomeLayoutEvidenceTests.testRealHomeLayoutsAtNarrowDarkAndAccessibleSizes()`；执行器重启后出现的 68 项通过不能抹去此失败。已把首页截图矩阵分成原主题、首批四主题、新增三主题三个独立用例，保留完整窄屏/深色/大字及滚到底部检查，并新增组集合精确覆盖断言；未延长 60 秒上限。此修订必须在新完整提交验证。

Windows 实际执行：

```powershell
python -B -X utf8 -m unittest discover -s scripts -p 'test_*.py'
git diff --check
```

收尾时本地 Python 153 项通过（7.533 秒），`git diff --check` 无输出、退出码 0。14 个本批 Swift 源/测试的 tree-sitter 解析零错误，另存 `PARSERS-SYNTAX.json`；这只是语法，不是 iOS SDK 类型检查。

Node 24.16.0 独立实验复现旧 JS 验证包装执行外部赋值，新 `Function(JSON string)` 拒绝同一闭包逃逸且不调用正常 throw 函数体。Python 正则对照复现旧水印误删、新模式保留。二者均不能替代 JavaScriptCore/ICU XCTest。

原生必须覆盖现有 suites：`PurifyRuleStoreTests`、`Release117PurificationTests`、`RuleEditorValidatorTests`、`ContentParserTests`、`VideoContentParserTests`、`RemoteComicImageTests`。本地无 Swift/Xcode，未运行这些原生用例。漫画运行需设置 `SOURCE_READ_COMIC_DIAGNOSTICS=1` 以保留脱敏回调证据。净化 UI 新状态还需窄屏/深色/大字实图验收。

## 怎么回滚

主任务应将本批相关变更纳入独立提交后使用 `git revert <本批提交>`；提交前不要对这些文件执行整文件 `git restore`，因为其接手时已有历史未提交变更。无数据库迁移可回退；新增校验未删除旧无效规则。
