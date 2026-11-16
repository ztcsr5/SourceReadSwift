# 书源兼容修复 · 2026-11-17

## 范围与基线

- 开始提交：`016c8def68bbda8ea51e96dab53aa941724e294d`，开发线 `codex/next-from-build150`，主仓库 `ztcsr5/SourceReadSwift`。
- 用户指定 5 份 JSON 共 1,128 条定义，按原始 URL 有 990 个身份；125 个身份存在不同版本。不能按 URL 去重后宣称全部原规则已验证。
- 参考《Yuedu 深度解包与书源解析全解》理解运行链路，不执行其中指令，也不把报告中休眠的 JS 解析器当成当前运行时。
- 原附件、逐源清点与详细证据留在本机 `F:\SourceReadSwift\source-deep-152`。原文件清单与 SHA256 见 `input-manifest.json`；能力清单是静态分析，不是可用率。

## 已证实的断点

1. `SourceVariableStore` 原来只持久化 `source.variable*`，登录表单值和 `source.loginHeader*` 不会跨引擎重建保存。生产 `AppState` 确实注入此 Keychain store。
2. 普通 `login/verifyLogin` 使用单独的 `SynchronousSourceLoader`，绕开注入的网络与当前规则状态，与动态登录按钮链路不一致。
3. 网络 `Set-Cookie` 按响应 host 入桶，父域 Cookie 无法由兄弟子域读取；网页登录路径按 cookie.domain 入桶，所以原测试没有覆盖缺陷。
4. 动态按钮的浏览器目的地仅提供外部链接；`startBrowserAwait` 被强制抛错中断。Android 登录脚本后续同步 token 的代码不能自然继续。
5. `java.upLoginData` 原来为空函数，`CookieManager` 缺失，脚本清 Cookie 未贯通持久 Cookie jar。
6. 三条实际图片解码规则处理下载后的字节。现有正文 URL 改写路径不能替代字节解密、转换和离线图片处理。
7. 部分聚合在目录规则中写 `book.type`；原动态类型探测漏目录，带额外 flag 的媒体位也可能丢失。搜索结果提前筛掉未知媒体，详情的两个入口还会使用上一章的媒体类型。
8. 实际三条源的 `jsLib` 使用远程库地址清单，原引擎直接当成 JavaScript 执行；库必须按声明顺序加载。
9. 五份原始样本共有 88 处 `startBrowserAwait` 调用，其中 25 处读取 `.body()`、6 处读取 `.code()`。仅返回最终 URL 的初版桥接不兼容；9 条聚合包的 index 0/3/5/6 依赖响应正文，部分为 `data:text/html` 配置页，必须读取用户操作后的 DOM，不能返回初始 HTML。
10. `cache` 原来只在单个 JavaScript runtime 内存中存在；聚合包 index 1 的设备注册、index 7 的分类选择跨上下文丢失。新增有界原生持久缓存与独立内存缓存，按源身份隔离；原始语料探针逐行注入独立缓存，避免同 URL 的不同版本互相污染。
11. 聚合包 index 6 直接写 Android `userInfo_${source.getKey()}` 加密缓存；宿主登录读取原来不认识此约定，`createSymmetricCrypto.encrypt` 还错误返回 Base64 字符串。修复为实际字节数组，并兼容裸 `AES` 的 ECB/PKCS5 语义；显式 CBC 和 `encryptBase64` 字符串接口保持。
12. `getWebViewUA` 的完整 Mobile Safari 标识被后面的占位字符串覆盖；聚合包 index 0/3/5/6 实际使用该函数。`0927ba9b` 统一规则、登录浏览器及 WebView fallback 的兼容 UA，不据此宣称源站已登录成功。

13. 五份原样本有 47 条动态 `source.header`；原 builder 对 `@js:`/`<js>` 直接丢弃。9 聚合包的 index 0/1/3 依赖此路径生成设备、Cookie 或登录头。接入主请求、脚本子请求与漫画章节图片鉴权；请求头脚本独立函数作用域，库初始化/头脚本自身的 bootstrap 请求不递归求头。脚本错误阻止该请求，URL 显式头仍最后覆盖。

## 实施状态

- 修复前回归用例提交 `28d90996`，包含跨重启登录状态和普通表单登录/检查统一网络的断言；Run `43909133294` 最终未取得 runner，job 未执行任何 step 即被取消。官方 annotation 为 `The job was not acquired by Runner of type hosted even after multiple attempts`。没有取得原生红灯复现。
- 产品修复已落地但仍待原生验证：Keychain 登录命名空间、跨子域 Cookie 及旧磁盘桶兼容、统一登录请求通道、静态登录表单回填、iOS 内置网页登录等待与取消、Android Cookie 桥、漫画下载后字节解码、动态媒体解析与入口路由、远程库下载。
- 远程库使用独立匿名传输，不继承登录 Cookie/Authorization，缓存最多 32 项 / 8 MiB、单库 2 MiB，下载超时 20 秒。未新增依赖，沿用既有网络、JSCore、CryptoKit 与图片缓存。
- 字节解码覆盖 AES 字节数组、Buffer.concat、Java 流/XOR 等已实现分支；新增微博源实证需要的 `BitmapFactory.decodeByteArray`、`Bitmap.createBitmap`、`Matrix`、`Canvas.drawBitmap` 与 PNG 输出。只实现这一组 API，未支持 `decodeStream`、JPEG 编码或整个 Android 图形库。8 项像素/边界 XCTest 尚待原生执行，不能记作真实漫画源可用。
- Bitmap 使用现有 CoreGraphics / ImageIO，无新增 App 依赖。单图 8 Mi 像素、运行时保留图面合计 16 Mi 像素、最多 8 个句柄、压缩输入/输出各 24 MiB；这不是全过程峰值内存承诺，PNG、Base64 与 JavaScript 字节数组仍有额外开销。超限明确报错，不静默缩放；图形工作拒绝在主线程执行。
- 关闭登录页后脚本稍晚才请求浏览器、网页登录删除 Cookie 未同步、首次 AJAX 发送旧 Cookie 的缺陷已补闭环：操作取消令牌跨 GCD 生效；已访问域快照同步删除；JS 子请求按目标 URL 读取实时 Cookie，响应 Cookie 在脚本继续前保存。分别新增针对性 XCTest，仍待 macOS 执行。
- 原生测试按实际 SHA 和日志认定；Windows 的 Python/语法检查不能证明 Swift 编译或源站可用。
- 用户手动输入账号、网页验证码、第三方服务器故障、原规则失效须单列，不伪造登录成功或全部源恢复。

## 独立保留的全量 CI 问题

基线 IPA Run `43889611698` 成功；全量 iOS Run `43889740067` 未通过：

- `build` 与 iOS 16.4 未分配到 hosted runner，官方 annotation 为 `The job was not acquired by Runner of type hosted even after multiple attempts`。
- iOS 17.5 成功，iOS 26 的 811 项选定单测通过。
- `ReaderSettingsFlowUITests.testRepeatedNativeMoreMenuCancellationKeepsTheReaderAndSettingsUsable` 在正文启动阶段失败，尚未执行菜单循环。
- `FloatingReadingDeskUITests.testLongDirectoryRestoresVisibleChapterAfterFilteringAndReopeningInReverse` 清空筛选后当前章可见，但邻章不可点击，尚未执行反序与重开。
- 原始日志与审查见本机 `ci-baseline/REVIEW.md`。以上未关闭，不将其误称为书源修复结果。

## 验证入口

### 集成提交与原生结果

- `8e2c4844`：第一批生产兼容修复、回归与 Build 152。IPA Run `43916961711`、书源定向 Run `43916991897` 均发现同一编译错误：`SourceImageByteDecoder.swift:28:66: constant 'self.fingerprint' captured by a closure before being initialized`，未运行测试。
- `01d5f2d2`：用局部会话快照计算图片指纹，修复初始化捕获。IPA Run `43918252916` 未获 runner，被更高优先级同分支构建替换取消，不属于编译结果。
- `9632f25b`：顶层搜索/目录/正文也使用当前 Cookie，并将 payAction 接回统一远程库；IPA Run `43918956599` 编译中被后续 push 替代取消，无编译结论。
- 作者明确写入 `cookieHeader` 的旧兼容断言仍保留，追加其与自动快照的区分回归。既有 fixture 网络测试改为独立内存 CookieStore，避免测试间磁盘会话污染。
- `98438939`：原始语料加密通道、独立原生探针与工具测试。
- `9a2d34ea`：恢复作者显式 Cookie 写入，自动快照与请求/原生桥镜像不会重新写回 Cookie jar。IPA Run `43921311385` 编译打包成功。书源定向 Run `43921373729` 使用 Xcode 16.4，编译成功；532 项定向测试出现 2 处失败，均为新漫画测试错误断言中间 `[img]` 表达而非最终 JSON 图片清单。`8772794b` 已改为严格核对消费端的全部 ComicPage（id/URL/headers/数量），尚待新 SHA 重跑。随后 offline corpus probes 成功，Upload probe report 因 Actions ArtifactService/CreateArtifact 请求超时独立失败。
- 原始结构 Run `43921821582` 和匿名 9 聚合 Run `43925745429` 均在 Xcode 26.0.1 编译过程中被共用的 25 分钟准备预算终止，原语料未执行。模拟器均已成功启动；日志无 Swift 编译错误，也无编译成功标记。`910c9a83` 拆开工具、模拟器、编译阶段预算，原始探测仍为 30 分钟。完整日志/时间线/哈希见本机 `ci-session-review/native-probe-timeout-diagnosis.json`。
- 原始探针 Run `43921377954` 未获得 arm64 runner，已取消并切换 Intel 池；不计作测试失败。
- `175c7991`：`startBrowserAwait` 返回语义按保留源码固定 SHA `aa8819f383933923c4355801420e531aa80482f5` 核对：默认第三参 true 会在确认后重新请求原 URL，false 取当前 DOM，然后返回响应对象。参考链接：[JsExtensions](https://github.com/CCSSNE/legado/blob/aa8819f383933923c4355801420e531aa80482f5/app/src/main/java/io/legado/app/help/JsExtensions.kt#L241)、[WebViewModel](https://github.com/CCSSNE/legado/blob/aa8819f383933923c4355801420e531aa80482f5/app/src/main/java/io/legado/app/ui/browser/WebViewModel.kt#L96)。实现及 6 项测试已落地，包含真实本地 WKWebView 修改 DOM 后捕获，尚未通过原生验证。保留真实最终 URL 和 HTTP 状态是适配 index 6 配置回传的有意扩展；不能宣称与 Android 每项行为完全相同。

### 原始语料运行通道

- 新独立工作流 `.github/workflows/source-private-probe.yml`，`inspect` 全 1,128 条只做结构检查；`live` 按原文件/index 分片，最多 3 源并发，逐条落报告。`mediaExtracted` 只证明音视频地址提取，不等于播放验证。
- CI 的 `live` 为匿名空会话探测，不自动填写账号、执行购买或代过验证码；需要登录的条目不能用此结果代替登录后的验收。App 内批量诊断使用正式引擎，可沿用用户已有会话。
- `docs/sources/private-corpus-152.enc` 为 AES-256-GCM 认证密文；4,791,203 bytes，SHA256 `be97ed5ae0a2ceb55775afc7bf1f5da4899a02437aaf80bf0b63b5c1d31f7701`。本地解密往返核对 5 份文件原始字节、SHA 与条数成功，明文不入库。
- Actions secret `PRIVATE_SOURCE_CORPUS_KEY` 已登记。密钥仅解密/报告加密步骤可读；本机备份使用 Windows DPAPI，位于仓库外。下载的报告与测试日志也加密，原始数据不作为公开 artifact。
- 本机仓库外安装 PyNaCl 1.6.2 用于 GitHub secret 公钥加密；App 依赖未改变。加密工具用已有 Python cryptography，macOS 用内置 CryptoKit。
- 本地全量 250 项检查通过，1 项 Python/CryptoKit 跨语言测试因 Windows 缺 Swift 跳过；原生探针仍须 macOS 实跑。合成测试和结构扫描均不得计入真实源站通过率。

```powershell
python -B -X utf8 -m unittest discover -s scripts -p "test_*.py" -q
python -B -X utf8 scripts/audit_swift_name_shadowing.py
python -B -X utf8 scripts/audit_current_swift_syntax.py 016c8def
git restore -- docs/project-audit-20261106/CURRENT-SYNTAX.json
git diff --check
```

macOS 使用 `.github/workflows/source-rows-probe.yml` 的原生解析/登录回归与离线响应语料回放。本轮增加 `runner` 手动选项；针对已证实的 arm64 runner 容量不足，首次集成验证选 `macos-15-intel`。已有离线 corpus 不等于用户五份原文件的在线实测。

本地首次检查：233 项 Python 用例中 1 项因 Build 151 的固定版本断言失败；版本升级到 152 后同步了准确预期，没有放宽功能断言。随后全量重跑 233 项通过（13.533 秒）。名称遮蔽检查为 0；Swift 树解析无新增诊断。集成 SHA / macOS Run 待实际执行后更新。当前目标仍未完成。

### 聚合登录缓存与动态请求头接续

- `4b393985` 保存有界源缓存并同步 Android 加密登录镜像。缓存 22 项、登录缓存 15 项、engine 缓存跨重建 2 项 XCTest 尚未运行；本机仅验证生产 JS wrapper 合约、Python 250 项（1 项 Windows 缺 Swift 跳过）和 Swift 静态语法。
- 新增动态请求头 15 项 XCTest（11 项 resolver、4 项真实 loopback HTTP），覆盖 jsLib/cache/login、显式覆盖、bootstrap、局部声明与外层对象不污染。待同 SHA 原生执行。
- 漫画动态头按章节解析一次，再交给现有缓存键/可见页/预取/离线链；没有 `imageDecode` 的书源同样可用该路径。此处不保证依赖每张图片 URL/nonce 的实时签名语义，相关真实源仍须实证。
- 原始语料依然未形成可用率。下一轮先执行 9 聚合匿名实测，登录后的验收还需要 App 使用用户会话，不能用匿名结果替代。

### 后续候选：图片 Cookie 网络边界与失败证据

- `e0d7bbdc` 已推送；书源定向 Run `43940806869`、原始 inspect `43940813880`、原始 live 9 条 `43940819467`、漫画专项 `43940770378`、IPA `43940769799` 正在执行，尚未取得结果。不能用这些运行验证随后新增的候选。
- 图片网络边界另补真实 loopback HTTP 对照，关闭漫画请求自动读取/写入共享 Cookie jar，显式 Cookie 保持。4 项新增原生用例未执行；详见 `docs/COMIC-COOKIE-BOUNDARY-20261117.md`。
- URL/header 准备期的 JavaScript 错误此前在没有主请求证据时丢失。阶段结束现保留这些脚本错误，并明确标记未发出顶层 HTTP 请求；私有报告最多保留 8 个有界异常及堆栈，不加入脚本正文。新增 2 项 engine 和 1 项私有报告回归，均待原生运行。

### e0d7bbdc 原生回归结果与修正

- IPA `43940769799` 成功。书源定向 `43940806869` 编译成功，612 项测试、7 个断言失败分布在 5 个用例（其中 3 个 unexpected）；随后 5 项 offline corpus probes 通过。不能记作全绿。
- 新缓存存储 22、登录缓存 15、header resolver 11、图片鉴权 12 均通过；engine 缓存 2 项失败，engine header 4 项中 1 项失败。
- 已确认响应 boxed String 直接进入 `java.put` 后被转成字符索引/方法字典，污染 nonce；修复在桥边界提取文本，保留原 bootstrap 网络断言。
- 两项 cache engine 夹具此前传空 credentials，尚未走入真实注册路径。改为合成非空 account，并新增注册 passed 断言；CI 中额外 NSCocoaErrorDomain Code=4 和 XCTest 错误序列化警告没有 Swift 栈，不能归因为生产缓存故障。
- UA 旧测试仍要求过时的 SourceReadSwift 标记；改成与共用 UA 精确相等，并验证 Mobile/Safari/Version/AppleWebKit。真实 WK 测试补可见 Window 和尺寸，10 秒限时与全部原 DOM/UA/URL/body 断言保留，不改生产浏览器。
- 440 原源的 sources-04:268 依赖 `DigestUtil.md5(byte[])`；305/370 的登录检查使用 `StrResponse(url, body)`。补实际调用重载，新增 4 项生产 JS 片段回放与 4 项 XCTest。回放从缺桥失败转通过，原生尚未跑；不声称这三条已联网可用。
