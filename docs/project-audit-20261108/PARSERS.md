# 解析、漫画传输与净化审查 · 2026-11-08

本批发现并修复了正文回退漏净化、段落合并、无效规则静默接收、规则保存失败仍显示成功、校验 JS 可逃逸执行、视频候选选错等问题。漫画超限测试已恢复真正的零正文条件；是否能在 4 秒内拒绝，仍须本批 SHA 原生运行确认。旧 `e2f4c7ff` 双系统通过仅是接手基线。

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

漫画测试没有改 `tooLarge` 期望、4 秒门限或累计字节上限。零正文分支并行启动独立 Foundation `URLSession` 对照，失败时输出：服务端接收请求/发完整响应头/正文计数、原生 response 回调是否出现、`task.response` 是否存在、预期字节数与完成错误码。如果独立系统与生产同时未收到 response，需继续定位系统交付约束；如果原生对照已收到而生产未完成，继续查生产 continuation/调度。当前未获得这一轮原生结果，不能先宣称根因已关闭。

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
- 本批对真实零正文超限仅修复了证据与夹具，未证明所有 iOS 版本的响应回调及时性。不要用 `declaredPrefix` 通过替代 `.declared`。

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
