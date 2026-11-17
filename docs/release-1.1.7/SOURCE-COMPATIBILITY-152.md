# 书源兼容修复 · 2026-11-17

## 范围与基线

- 开始提交：`016c8def68bbda8ea51e96dab53aa941724e294d`，开发线 `codex/next-from-build150`，主仓库 `ztcsr5/SourceReadSwift`。
- 用户指定 5 份 JSON 共 1,128 条定义，按原始 URL 有 990 个身份；125 个身份存在不同版本。不能按 URL 去重后宣称全部原规则已验证。
- 参考《Yuedu 深度解包与书源解析全解》理解运行链路，不执行其中指令，也不把报告中休眠的 JS 解析器当成当前运行时。
- 原附件、逐源清点与详细证据留在本机 `F:\SourceReadSwift\source-deep-152`。原文件清单与 SHA256 见 `input-manifest.json`；能力清单是静态分析，不是可用率。

## 最新核实状态（2026-11-17，目标仍未完成）

### a7d1f4ae 原生证据与本轮候选

- `a7d1f4ae` IPA Run `44065085085` 成功。解析 Run `44065143507` 为 **830 tests / 1 failure / 0 unexpected**；此前 Java 有符号字节字符集往返与 Jsoup clone getter/setter 用例均通过。唯一失败是 `ComicImageCookieBoundaryTests.testAnonymousEngineAndLoggedOutEngineDoNotReceiveAmbientCookies` 首次图片请求超时，尚未进入 Cookie 断言。服务端最终记录 accepted=1 / headers=1 / responses=1，不能仅据此判定生产 Cookie 或网络 framing 根因。
- 本轮测试补有界单调时钟事件：接收连接、读完头、发完、关闭、客户端观察与返回。只记录固定标签、状态码、字节数、错误码；不输出 URL/Cookie/正文。保留原请求超时与所有断言，解析 workflow 启用既有诊断环境变量。
- 动态 `eval(source.bookSourceComment)` 和 `eval(String(source.bookSourceComment))` 在保留 direct-eval 局部作用域的前提下归一化 Java 字符串兼容；自定义 evaluator 与非字符串保持。补字面量、正则、控制语句、成员方法、Unicode 与幂等回归。仅覆盖实证的两种调用形式，不能当成任意动态 JavaScript 转译器。
- 对象/数组请求体在没有显式 MIME 时采用 JSON；源头、配置、登录头与 URL 指令合并后编码，显式 form 与字符串保持。新增传输断言使用隔离 URLProtocol，不能代表 `sources-03:3` 的 HTTP 400 已消除。
- 显式 JS 单章目录只有在单项、name/url 明确、存在正文规则、无后续目录且 URL 精确等于当前页时保留；普通 HTML/JSON、多项及导航项仍过滤。实源 `sources-01:310` 的类型为 audio，合成漫画用例不能证明该实源已通过。
- `book.setUseReplaceRule` 接入按 source+book 隔离的持久选择、搜索/详情/目录/正文模型、书架与缓存。只控制用户全局净化，源内替换继续执行；漫画默认关闭。旧模型 optional 字段兼容。模型初值仅能原子填补未存选择，未修改开关的请求及迟到预加载缓存不得覆盖新选择。
- 文本全局净化改为正文分页与字段脚本结束后执行一次，采用最终书级选择，避免第二页或标题规则关闭净化时出现半章已删、缓存却标为未净化。源内替换仍按现有逐页流程执行；音视频直链/漫画图片旁路保持。全局 JavaScript/跨页正则的输入粒度由单页变为整章，此兼容变化需原生回归验证。
- `sources-01:76` 已定位 leading-dot JSONPath 返回类型差异：固定上游依赖 Jayway 2.10.0，实际 Java 对照 `.data.content` 返回数组、`$.data.content` 返回标量；旧归一化丢失数组导致后续 `result[0]` 只取首字符。修复在 JS 链执行前保留深层查询数组，删除列表空结果时重跑脚本的兜底，新增 3 项 XCTest。Java/Node 合成对照已执行，原生与实源尚未执行；安全记录位于仓库外 `source76-oracle/evidence.json`。
- `sources-02:27` 已确认脚本选择链存在 `setContent` 新文档被旧 src 覆盖、Legado class/tag/@ 选择规则未分派、`java.getElement` 集合返回被取 first、选择脚本末句返回值丢失四个相连断点。候选复用已有 HtmlRuleExtractor/文档绑定及 JSCore completion，不重复执行源脚本；`ruleResolver.getElement` 单节点契约保留。样本响应正文未留存，不能承诺修后实源已通过。
- eval 新改写保守保护 `}` 后含斜线的歧义区间，不转译对象字面量除法表达式内的 comment eval；普通直接调用仍兼容。这一明确边界避免把块结束后的正则字面量改坏，不宣称实现完整 JavaScript 语法解析。
- 本机全量 Python 初次因 Chrome 启动超时连带出现 8 个错误（248 tests）；随后单独浏览器 5 项通过，全量重跑 **256 tests / OK / skipped=1**（Windows 缺 Swift）。名称遮蔽 0、diff check 通过。后续新增 Swift 候选仍未编译，不能使用这些检查或旧 SHA 原生结果宣布通过。
- 接续收取最后一次 Python 进程：**256 tests / 14.451 秒 / OK / skipped=1**；未重新启动重复检查。已提交 `ad113797`（请求体）、`1590ab57`（JSONPath）、`11c37f1e`（书级状态/目录/净化与缓存）；新 Swift 仍待同 SHA macOS 编译与 XCTest。
- `107bb113` 提交选择器 completion、动态 comment eval 和相关桥接回归。后续复核补齐 `break/continue/debugger` 换行/label 后正则保护，Node 镜像算法 48 组通过；这不是原生执行证据。runtime 新增只检查语法、不执行脚本的 `isRuleScriptSyntaxValid`，供失败重试区分顶层 return 与运行期伪装 SyntaxError。
- 新发现且正在修复：搜索列表在 JSON→HTML fallback 会重跑带副作用的列表脚本；字段组合规则为确定分隔符也会重复执行分支。候选改为保留一次选择的实际类型，并复用既有字段解析。明确空、运行异常不得回退重放，init 与原始响应绑定分开。
- 下一独立缺口：普通请求未调用源 `loginCheckJs` 响应钩子，现有调用仅在手动验证登录。固定 Legado 上游对搜索/发现/详情/目录/正文首请求调用，内部分页不调用；`getStrResponse(null,null)` 是当前请求重发，不是 URL 参数。已定位调用契约，尚未修复/验证，不能当成所有相关实源失败的已证实根因。
- 搜索选择修复已收敛：保留 HTML/JSON/原生节点实际类型、逐行文档绑定与裸 `java.` 规则；明确空和异常不重放，伪装顶层 return 的运行期 SyntaxError 通过无执行语法检查排除。新增 10 项搜索回归、1 项字段组合副作用回归；尚未在 macOS 运行。最终本机 Python **256 tests / 35.882 秒 / OK / skipped=1**，名称遮蔽 0、34 个候选 Swift 文件无新增 tree-sitter 语法错误，diff check 通过。
- `loginCheckJs` 后续专项冻结：原始 1,128 条中 36 条有非空配置；`sources-02:4` 的分支返回登录头 setter 的结果，不能简单拒绝所有非响应返回值。隔离测试草稿留在未跟踪 `SourceReadSwiftTests/SourceResponseLoginCheckTests.swift`，本批不提交、不声称通过；先收取当前修复的 macOS 和定点实源证据。
- 接续：精确重测 9 聚合、`sources-01:76/181/310/325`、`sources-02:27` 与 `sources-05:8`，再补当前 SHA 全量 1,128 条。登录后保持、漫画实收字节/解码与音视频实际播放仍须各自证据；不以匿名首结果首章结果代替。

### f3b41e1d 检查点与桥接修复候选

- 解析 Run `44051412323` 编译成功，**827 项 XCTest / 2 项失败**：Java 有符号字节的字符集往返与 Jsoup clone 后的属性/文本写入。IPA Run `44051152821` 成功，不能代替测试通过。
- 同 SHA 四份加密报告已下载、解密并核对索引：`44051418979` 九聚合为 **4 passed / 3 failed / 2 requiresLogin**；`44051424711` 仅测 `sources-01:76,181,310,325`，1 通过、3 失败；`44051430579` 仅测 `sources-02:27`，失败；`44051436095` 仅测 `sources-05:8`，通过。合计仅覆盖 **15 条，6 passed / 7 failed / 2 requiresLogin**，不是全量 1,128 条成绩；`sources-04` 无此 SHA 的运行。
- 候选修复复用 `__javaBytes` 处理 Java byte 的无符号位模式；Jsoup 的 7 组节点与 1 组集合 getter/setter 由单个 `JSValue` 导出入口按缺参分派，保留原 Swift 方法和节点身份，不改 `copy()` 或扩散 Proxy。原失败断言保留，另加原生 clone 对照、空字符串/链式写入与各节点返回路径 3 项 XCTest。
- 本地 Python **256 tests / OK / skipped=1**（缺 Swift）、名称遮蔽 0、以 HEAD 对比 3 个 Swift 文件无新增语法诊断、diff check 通过。候选尚未在 macOS 原生验证，不记为通过。
- 尚未关闭的明确缺口：`sources-01:181` 的动态 `eval` 绕过 Java `.length()` 兼容；`sources-01:310` 的显式单章同页目录被过滤；`sources-03:5/6` 缺 `book.setUseReplaceRule`。其他失败须按分段输入输出继续定位，不能以服务端问题概括。私有原始报告与安全摘要保存在仓库外 `D:/CMoved/Documents_IOS/source-compatibility-review/private-<Run>/`。

### f34660d9 原生检查点与随后兼容修复

- `f34660d9` IPA `43982663668` 已成功。解析专项 `43982744818` 原生回归为 **714 tests / 1 failure**：真实 Security Keychain 跨 store/engine 恢复通过（0.742 秒），4 项新增 URL 保真用例及原有重复域名用例通过。唯一失败是 807 章复杂目录的 15 秒预算，实际计时 20.671 秒，未放宽断言。旧 1396 章用例本次耗时 11.850 秒；与旧 runner 的 27.944 秒不是受控性能对照。
- 同 SHA 原始九聚合 `43982749343` 已核原文件 SHA/index：**4 passed / 2 requiresLogin / 3 failed**。index 1、6、8 的目录全部在原 15 秒预算内通过，分别 1396/807/597 章、13.747/9.219/14.013 秒；index 1 和 8 首章也通过，index 6 正文仍为版本/身份提示。index 3 仍目录失败、index 5 仍正文提示，index 0/2 仍需账号登录。
- 九聚合新报告 SHA256 `972d21320e6c24f85674d86e5dc92ea633e8a9008ea5b9e331e41f643792e394`；安全逐行摘要位于仓库外 `D:/CMoved/Documents_IOS/source-compatibility-review/private-43982749343/safe-live9-comparison.json`。匿名探针完成不等于登录、分类页或全书全章节可用。
- `sources-05` 最后 64 条 Run `43958023110` attempt 2 已取得并核对报告，原 SHA `1a98f5da` 的 164 条完整结果为 **51 passed / 113 failed**，无重复遗漏。五份初轮已全部收齐；按各条最近一次结果（版本混合）累计为 **308 passed / 807 failed / 7 mediaExtracted / 6 requiresLogin = 1128**。这不是当前 HEAD 全量通过率，媒体播放和真实账号重启保持尚未验收。
- `79d9964e` 为实际失败 `sources-02:27` / `sources-05:8` 增补 `cookie.replaceCookie` 和 `Charset.forName`。Cookie 按固定上游同名合并、空值无操作，沿用持久 Cookie jar；字符集复用现有编码转换，未声称覆盖全部 Java Charset。新增 3 项原生回归尚未运行。
- `ad56755f` 仅给私有探针增加表单字段结构：保留白名单字段是否存在、空值、重复，不保存任何值。无显式 Content-Type 时仅严格识别已知字段并标为 `form-like`，不据此断言 CFNetwork 的实际上线 MIME 类型，也不据此认定 index 3 的 HTTP 400 根因。
- `f4d9928e` 给 Jsoup Element 增补深克隆，沿用 SwiftSoup `copy()`，不污染原节点；新增原生独立性/相对 URL 回归未运行。原始 `sources-01:325` 仍须定向重测后才能更新可用结论。
- `acef5c6f` 将 HTML 搜索结果和目录字段的 `result` 绑定到当前选中行，同时保留页面级 `body/html/src`；目录元数据父节点回退时绑定父元素。新增 HTML 多行搜索/目录字段回归。此修复由 `sources-01:310` 的 `result.attr()` 行为断点导出，须用原 index 定向重测确认。
- `3b2149b8` 为固定 `body/html/src` 原始字符串复用同一 JSCore 值，规则仍逐次重新绑定，最多缓存三项且 runtime 释放时一起释放；新增变文、作者重赋值、非字符串和嵌套恢复断言。目的为降低大目录逐字段重复跨桥成本。它尚未在新 SHA 原生计时，不能说 15 秒性能门槛已经达成。
- `e9e50723` 在混合 Java 对象规则中适配裸标识符 `.length()`：数值属性按值返回、真实方法保留 `this`、非 callable 继续报 `TypeError`；恢复 5 个此前放在非 XCTest fixture 类中的旧断言，并新增边界用例。Node 合成执行通过不等价于 Apple JavaScriptCore 原生测试通过。
- `0ae466a4` 把 `LegadoJavaScriptCompatibilityTests`、`LegadoNativeBridgeTests`、`HtmlRuleExtractorTests` 纳入源解析 CI。上述新增提交尚未触发或完成 macOS 原生回归；不能用 `f34660d9` 的 714 项结果替代。
- 参考 MD 的 §3.1–3.4 明确活动实现是 `ModernParserBridge`，`ruleEngine.js` 仅休眠；§12 也说明两者逐条语义差异尚未做差分验证。后续参考源码固定 SHA `cbb9a6a5d59933ecaf42c651d7f9583a34925cd1`（晚于报告推定 IPA 时间窗）只作为独立行为参照，不作为当前目标 App 的构建版本证据。
- 2026-11-17 续跑本地复核：Python **256 tests / OK / skipped=1**（Windows 缺 Swift）、名称遮蔽 0、以 `69729734` 对比 Swift 语法 **327 files / failures=[]**、diff check 通过。检查生成的 `CURRENT-SYNTAX.json` 已恢复，未将其混入本轮提交；这些结果不能代替上述新增代码的 macOS 编译和 XCTest。

### 本次续跑取得的新证据

- 当前 `f0415c78` IPA `43960233024` 成功；解析专项 `43960383009` 708 tests / 4 failures，均来自真实 Keychain 同一个恢复用例，错误 `OSStatus -34018`。旧 `1a98f5da` 的 `43955671025` 同样为 707 tests / 4 failures。其余断言与后续离线 corpus 不能冲抵该失败。日志保存在仓库外 `D:/CMoved/Documents_IOS/source-compatibility-review/`。
- `8aa74dda` 为解析专项及全量单测宿主恢复模拟器 ad-hoc 签名，未修改生产存储或放宽登录断言；新 run `43981279002` 在测试前失败：`SourceReadSwiftTests` 缺少 Info.plist。随后在 `project.yml` 为单测 target 增加自动生成 plist 和独立 bundle ID，仍需新 SHA 原生验证。
- `1a98f5da` 九聚合 `43955675613` 已核原件/index，仍为 2 passed / 2 requiresLogin / 5 failed。index 1、6、8 的目录 HTTP 已分别在约 0.8、0.3、1.2 秒返回，但阶段两次耗尽 15 秒；index 6 明确返回 807 项数组。index 3 的目录 POST 收到 HTTP 400、JSON `data:null`，不能称为空目录兼容已解决。index 5 正文仍返回源版本/身份提示。
- 同 SHA exact8 `43955681960` 已核 index `103,109,113,139,154,160,184,197`：7 failed / 1 mediaExtracted。139 这次提取到音频 URL，但未播放；154 不再出现先前 TDZ，现止于网络错误，未全链通过；113 的三张采样均为 `NSURLErrorDomain -1003`，没有下载到图片字节。
- `sources-01` 五片全部原 index 0–463 无遗漏：117 passed / 341 failed / 6 mediaExtracted；300 分片 `43957920425` 的工作流失败来自另外两项合成探针测试，不代表这 100 条未执行。`sources-02` 的 `43957968091` 完整 51 条：13 passed / 34 failed / 4 requiresLogin。`sources-05` 前 100 条 `43957995898`：23 passed / 77 failed。
- `sources-05` 后 64 条 `43958023110` 已执行并加密，但 Upload encrypted evidence 的 CreateArtifact 超时，没有可下载报告，不能计入已核验结果。已请求同一 run attempt 2 补跑，未重复派发其他已完成分片。所有通过数仍仅覆盖首搜索结果到首章，真实登录保持/音视频播放验收均未完成。
- `c15bbede` 修复请求 builder、动态 URL 和搜索归一化误截断第二个 HTTP 地址；保留 query/fragment/代理路径内嵌 URL，只折叠重复开头同源地址，新增 4 个 XCTest；本地 Python 255 tests / OK / skipped=1，原生待新 SHA。
- 目录性能候选仅复用固定的 `source/book/chapter` 桥接安装函数，每次仍绑定当前对象并安装原方法，不缓存作者规则结果。原 1396 章合成用例 `f0415c78` 耗 27.944 秒；新增 807 章完整字段核对并要求现有 15 秒预算，保留原用例。Node 对生产三段脚本的前后重绑定对照通过，尚无 JavaScriptCore 提速结论。

以下为先前检查点，以上述新证据更新对应运行状态，不将旧成功归于新提交。

- `c9d597fc` 的 IPA Run `43945225638`、漫画专项 `43945225740` 均成功。解析专项 `43945341550` 已取得 622 项测试、2 项失败（1 unexpected）的日志，最终因整个 job 的 30 分钟预算结束而 cancelled；后续 corpus 仅 RowsParity 114/mismatches 0、Rows suite 1/0 和 SearchURL 前两项完成，TOC 未开始，不能记全绿。后续本地提交不能引用该包作为验收。
- 此次原生通过：engine cache 2/2、engine header 4/4、JS runtime 44/44、登录缓存 15/15、缓存存储 22/22、header resolver 11/11、图片请求头 12/12、Android bridge 4/4、Bitmap 8/8、图片字节规则 4/4。失败是图片 Cookie 边界用例的首个本地 HTTP 请求超时（尚未走到 Cookie 断言），以及真实 WK inline DOM 用例的 10 秒导航等待超时；其日志有约 44 秒 WebPrivacy 冷启动阻塞。保留实测失败，不以其他通过项冲抵。
- `e0d7bbdc` 原始聚合 Run `43940819467` 已实际完成 `sources-03` 的 9/9 条：2 条首结果首章全链通过、2 条需登录、5 条失败。该 run 的 success 仅表示探针完成。明细如下，序号均为原文件零起点 index。

| index | 实际覆盖与停止位置 |
|---:|---|
| 0 / 2 | 搜索被判定需登录；匿名探针不代表登录后结果 |
| 1 | 搜索 23 条、详情通过；目录两次 15 秒超时 |
| 3 | 搜索 9 条、详情通过；目录 JS 的 `JSON.parse(response).data.map` 链遇到 null；旧报告不能区分顶层 null 与 data null |
| 4 | 搜索 8 条、目录 597 章、首章 134 段，通过 |
| 5 | 搜索 12 条、目录 15 章；正文返回更新书源提示 |
| 6 | 搜索 12 条、目录 807 章；正文返回更新书源提示 |
| 7 | 搜索 120 条、目录 1 章、首章 408 段，通过 |
| 8 | 搜索 10 条、详情通过；目录两次 15 秒超时 |

- index 5 / 6 的内容请求携带原规则固定版本常量，分别为 `26.10.9` / `4.11.5.1`。未发现它们通过缺失的 iOS/Android appVersion API 生成版本号；当前证据支持远端版本门槛，不能改掉公告检测当作修复。index 1 / 8 的约 30.3 秒来自 15 秒限时 × 2 + 300 毫秒重试，不足以判断耗时落在网络还是同步解析。
- 原始 inspect Run `43940813880` 完成 1,128/1,128 条结构扫描，无网络可用率含义。`sources-04` 的 440 条已在 `c9d597fc` 分为 5 片运行：`43945347181`、`43945352103`、`43945358324`、`43945365334`、`43945371028`；必须以解密报告中的原文件/index 核对分片和执行数，不能把提交运行当作完成。其余三份原件尚未全量在线验证。
- `cdcd4b41` 将音视频播放接入动态请求头、实际流 URL 的 Cookie 和当前登录状态；保留 URL 显式头优先级，新增 10 项鉴权/迟到结果隔离测试。无新增依赖、存储格式迁移或 UI 外观改动。AVPlayer 的 HLS 子请求及重定向鉴权传播仍未验收。
- `2c4f5c3c` 为私有探针增加最多 64 条结构化传输记录与 5 项测试，记录请求完成/挂起、时长、状态码、JSON 顶层及固定字段类型；不保留 URL、请求头值和响应值。范围仅 `SourceNetworkClient` 调用，不展开该 client 内部重定向/重试，也不覆盖独立图片下载器或 AVPlayer 网络。漫画图片鉴权/解码脚本执行后会再次取快照。
- `48d66e6c` 让 Cookie 读/写失败可观察，网页登录保存失败留页，脚本写删不虚假确认；设置清 Cookie 同步清 WebKit/共享容器，未扩大为清除登录账号或登录头。新增 7 项回归及 1 项真实 Security Keychain 隔离命名空间测试，后者仍只重建 store/engine，未覆盖 App terminate/launch 的全 UI 流程。
- `3824ee64` 修正原文件 `sources-04:109/:184` 的错误分类：底层返回“无法连接到服务器或域名未解析”，之前因“解析”二字被误归 parser；没有证据支持修改两条规则本身。
- `66e80e8d` 修复本地测试 HTTP 夹具单连接串行阻塞的问题，新增首连接空闲时第二连接仍能取图的回归；可移植真实 TCP 实验已复现旧逻辑并验证并发服务修正，但不能证明 c9 的首次超时必然由此造成。WK 夹具按已有测试方式将冷启动准备单列为 60 秒，真正 data URL 导航仍为原 10 秒，并保留全部 DOM/UA/URL/bytes 断言；未修改生产浏览器或声称打开耗时合格。
- c9 的 `sources-04` 五片已实际完成全部 440 条，原文件 SHA 与 0–439 index 已核对，无遗漏或重复：123 passed、316 failed、1 mediaExtracted。这里只是首结果/首章范围，实际媒体播放与登录保持的验收数均为 0。主要停止位置为搜索超时 145、搜索空结果 49、搜索拒绝访问 23、搜索网络失败 23、搜索 JavaScript 失败 10、目录空结果 26、目录超时 10；不能把这些全部归为缺失 Android API。`sources-04:103` 配置了资源嗅探，当前匿名原始探针禁用 WebView，不能拿它的媒体提取失败代表已覆盖浏览器路径；后续报告显式标注此限制。
- `a00e9de2` 修复 `sourceRegex` 返回值：按固定 [Legado BackstageWebView 源码](https://github.com/CCSSNE/legado/blob/aa8819f383933923c4355801420e531aa80482f5/app/src/main/java/io/legado/app/help/http/BackstageWebView.kt#L261) 返回完整匹配资源 URL，保留签名 query；默认区分大小写、全串匹配，作者 `(?i)` 可用。资源 URL 模式不读取或 clone 音视频响应体；补 DOM/currentSrc/timing 捕获和原 30 秒总限时内的异步等待，无命中不会用 HTML 冒充播放地址。现有正文 helper/断言保留；18 项 XCTest 未运行，Node 执行生产脚本已验证。跨域 iframe、LiveContainer 无头 WebKit 和实际 HLS 播放仍不能由此证明。
- `7d4daf3d` / `c704bc3b` 补图片 URL 哈希、HTTP 状态、实收字节与网络错误码观察，默认关闭且原失败类型不变；私有报告按原文件/index/采样位置关联，超时样本各用独立收集器。正文只记录结构/长度，新增 `indices` 选项只重测精确失败行，仍保留所有未执行行，未改变原件身份。解析专项总 job 预算从 30 调至 60 分钟以容纳已实测的编译/回归/证据上传，单用例和原源阶段限时不变。
- `0ccb7eaf` 修 `sources-04:154` 的已证实 Rhino/JSC 差异：固定参考版本实际使用 Rhino 1.8.1，合成 Java 对照确认 `let key=java.encodeURI(key)` 可读取并更新宿主 key，而 JSC 报未初始化。仅搜索 URL 上下文的唯一顶层自引用 key 声明适配；支持实际规则的相邻声明 ASI，const、块/函数内绑定、重声明及不明确语法不改。8 项原生测试待执行；Node 只验证替换原语语义，不冒充 Swift scanner 执行。无新增 App 依赖，原始源未改。
- 本机最新执行：Python 255 项通过、1 项 Windows 缺 Swift 跳过；Swift 名称遮蔽 0，语法树对比无新增错误，`git diff --check` 通过。以上新增 XCTest 尚须后续提交在 macOS 上验证。

### 后续原生验证检查点

- `1a98f5da18e9ed10f28c13ba4f0fcf72dcd59d5c`：视频与朗读专项 [43955614933](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43955614933) 已 success，已取日志核实 72 tests / 0 failures。原日志为 1,266,608 字节，SHA256 `5458fb196461fd64fdf52fbf8291beee3e949c29b6cb70d96c20bb1dfdfd277f`，保存在外部 `ci-session-review/run-43955614933-media/`。此专项不能证明原始音视频源的实际播放全部通过。
- 同 SHA 的解析专项 [43955671025](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43955671025) 已编译成功并进入离线解析回归；漫画专项 [43955614941](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43955614941) 已编译成功并进入图片/拼章/控制回归；IPA [43955614924](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43955614924) 仍在构建，均须读取最终结果。
- 同 SHA 的九聚合重测 `43955675613`、八条精确失败重测 `43955681960` 仍在执行。精确 index 为 `103,109,113,139,154,160,184,197`；未取得报告前不更新它们的可用结论。
- 未测原件已按原 index 派发：`sources-01` 的 `43957847266` / `43957870209` / `43957895376` / `43957920425` / `43957943260`；`sources-02` 的 `43957968091`；`sources-05` 的 `43957995898` / `43958023110`。全部针对 `1a98f5da`，记录派发不代表执行完成。选择、SHA 与运行关联保存在外部 `1a98f5da-remaining-dispatch.json`。
- `a5bfc97f`：补审发现搜索关键词适配器会误将 `object.\nlet` 的合法属性访问识别为新声明。增量只给声明边界补点号排除，新增普通/可选链与 `let` / `const` / `var` 六种保持原样断言。本地 Python 255 tests / OK / skipped=1（Windows 缺 Swift），名称遮蔽 0、语法审查 92 files / failures=[]、diff check 通过。此增量不包含在上述 `1a98f5da` 的 CI 结果内；原生新增用例未运行，无新增依赖或数据迁移，单独回滚命令为 `git revert a5bfc97f`。
- 登录身份审查确认网页登录固定 UA，而正式书源请求可使用作者配置的 UA；这是代码行为差异，尚无具体站点因绑定 UA 而登录失效的证据，因此未直接更改浏览器身份或转发全部登录头。现有登录测试覆盖 Cookie/登录字段/登录头/缓存恢复，真实 Keychain 测试仍不等于 App 杀进程后再启动的实际账号登录验收。

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
