# SourceReadSwift 下一大阶段施工计划

## 目标

把当前可构建的 SwiftUI 阅读器推进到可长期使用的原生 iOS 产品节点：高刷设备流畅、EPUB/RSS 可完整阅读、书源和规则可诊断编辑、阅读器支持朗读与自动推进，并持续完成 Flutter 功能 parity。

## 施工规则

- 以“大阶段”为交付单位，不再为单个小修频繁打断。
- 每个大阶段完成后统一提交、推送到 `ztcsr5/read`，再等待 iOS 和 unsigned IPA Actions。
- Windows 只做源码、测试、静态检查和 Git 操作；Xcode 编译/测试由 GitHub Actions 完成。
- 不宣称真机 120 FPS，直到 ProMotion 真机实测；CI 只证明编译与测试。

## 当前执行口令（2026-09-02）

- 主路线固定为原生 Swift/SwiftUI，不再回退到 Flutter 运行时。
- 交付按“大阶段”推进：阶段内连续施工，阶段末一次性提交、推送和跑 Actions。
- 高刷新目标为“允许 ProMotion 设备使用系统最高刷新率，并清理阅读热路径掉帧源”；只有拿到 ProMotion 真机或 Instruments 证据后，才把 120 Hz 写成实测结论。
- Windows 端负责源码、fixture、静态检查、Git；GitHub Actions 负责 Xcode 编译、XCTest 和 unsigned IPA。
- 每次阶段回报只包含：提交 SHA、Actions run、artifact、已验证项、未验证项和下一阶段入口。

## 大阶段验收门槛

每个阶段必须同时满足以下条件才算“阶段完成”：

1. 代码和测试变更通过 `git diff --check`。
2. iOS workflow 的 build/test 成功；失败必须读取 annotations 后修复并重跑。
3. unsigned IPA workflow 成功并产出可下载 artifact。
4. `progress.md` 记录本阶段范围、证据、未验证项和回滚点。
5. 不得把“代码已提交”或“Actions 已排队”写成“功能已验收”。

## 阶段 1：性能与内容基础闭环

状态：进行中

- 修复高刷新协调器的 SDK 兼容性。
- 完成 SwiftUI/阅读器热路径 profiling 埋点。
- EPUB：路径编码、OPF/spine、正文抽取、目录、缓存、阅读进度。
- RSS：Feed/Atom 列表、文章详情阅读、HTML 正文抽取、失败 fallback。
- 验收：Actions 编译、单元测试、unsigned IPA；保留性能 signpost。

### 阶段 1.1：高刷与阅读热路径（当前优先）

- 保留 `CADisableMinimumFrameDurationOnPhone = true` 和 `FrameRateCoordinator`，确保 ProMotion 设备不被应用主动锁到 60 Hz。
- 以 signpost、主线程任务、分页/布局、图片解码和网络回调为观测点，逐个消除阅读页长任务。
- 禁止在滚动/翻页热路径执行同步磁盘 IO、整本重排版和重复 JSON/HTML 解析。
- 对自动翻页、朗读高亮、章节切换增加状态互斥，避免多个定时器或任务重复驱动 UI。
- 验收分两层：CI 证明编译/测试；真机或 Instruments 再证明实际 120 Hz/帧时间。

## 阶段 2：书源诊断与规则编辑

- 建立 `SourceReadSwiftTests/Fixtures/` 书源 fixture 集。
- 覆盖 Legado HTML/JSON/JS、POST、分页、JXNode、headers/cookie/status。
- 规则编辑器支持分组编辑、语法校验、本地样本预览、单步执行、日志和导出。
- 书源详情测试支持搜索→详情→目录→正文完整链路。

### 阶段 2A：Legado JS compatibility gap audit（当前已开工）

- 对齐 Flutter `LegadoJsEngine` 的高频兼容面：`getStr/getJson/putJson`、默认值语义、字节/Base64/Hex 转换、`postForm/openUrl`、全局 helper。
- 补齐常见 Java/Android 命名空间占位：`java.net.URL`、`java.security.MessageDigest`、`javax.crypto.Mac/SecretKeySpec`、`java.io.ByteArrayInputStream`。
- 保留原生 SwiftSoup/JavaScriptCore 路线，不引入 Flutter runtime；所有网络通过现有 `RuleExecutionContext` mock/handler。
- 以 fixture + XCTest 锁定 API 行为，阶段末统一提交、推送并跑 iOS build/XCTest 与 unsigned IPA Actions。

### 阶段 2B：991 书源真实诊断数据复盘与兼容性收口（2026-09-28）

本阶段只做诊断数据分析、计划拆解和后续验收定义。本轮不修改 Swift 源码，不访问诊断 JSON 中的真实书源 URL。诊断数据来自 `C:/Users/Edc21/Documents/xwechat_files/wxid_rpsqr5rjmyc222_4e8b/msg/file/2026-09/轻阅书源诊断数据_1790551476.json`，SHA-256 为 `334509BBD6EC00045E738611A6045995DF6CA4C132E19D9B94B964E12E8A1901`；关键词为 `重生`，采集时间为 UTC `2026-09-27T21:38:12Z` 至 `2026-09-27T21:55:10Z`（中国时间 2026-09-28 05:38:12–05:55:10），墙钟耗时约 16 分 58 秒。该文件可按 UTF-8 正常解析，之前终端出现的乱码属于输出编码问题。

#### 诊断基线与漏斗

- 991 个报告、2,859 条阶段记录、991 个唯一 source URL、552 个 source name；有 146 个名称映射多个 URL，最多一个名称映射 37 个 URL，因此 URL 作为稳定身份、名称作为显示字段的方向正确。
- 阶段记录状态：`passed=2,402`、`failed=225`、`warning=217`、`blocked=15`。按报告聚合后，四阶段全绿 534 个（53.9%），非全绿 457 个（46.1%）。
- 四阶段漏斗：Search `671/991=67.7%`；Detail `641/671=95.5%`；TOC `556/641=86.7%`；Content `534/556=96.0%`。Content 的 96.0% 只代表进入 Content 的源，最终端到端全绿率仍是 `534/991=53.9%`。
- 首个非绿色阶段：Search 320 个，约占 457 个非全绿报告的 70.0%；TOC 85 个；Detail 30 个；Content 22 个。当前最大瓶颈是搜索规则、搜索 URL/参数和搜索阶段的兼容性，不是正文渲染。

#### 失败分类与兼容性证据

- 主要 failure code：`empty-result=200`（当前全部按 warning 记录）、`parsing=131`、`network=91`、`blocked=15`、`timeout=14`、`invalid-source=3`、`javascript=2`、`unsupported=1`。这些数量合计 457，覆盖所有非全绿报告。
- Search 典型问题包括 URL 格式非法或解析异常（`-1000`）、域名无法连接、普通 HTML 搜索为空和 JSON 搜索为空。TOC 典型问题包括 `Chapter list is empty`、`JSON chapter list is empty`、`ruleToc.chapterList is empty`。
- 真实兼容性样本包括 `title.select is not a function`（书源预期 Jsoup Element，但桥接值不支持 `.select`）、`form.attr` 未定义、`getWbiEnc` 未定义和 `JSON Parse Unexpected EOF`。`www.linovel.net` 类型样本能通过 Search 与 Detail，但在 TOC 因 `title.select` 兼容问题失败，适合做 Search→Detail→TOC 回放 fixture。
- API 类书源还出现 invalid authentication、缺少小说 ID、缺少 device/version/brand/source/client name 等业务参数错误；`api-bc.wtzw.com` 类型记录同时存在 Content 通过和网络失败，适合验证间歇性网络、重试和隔离策略。
- `empty-result` 不能直接等同于源损坏，必须区分“关键词确实无结果”“搜索请求参数失效”“规则解析为空”和“API 返回业务错误”。当前不应依据一次诊断直接批量禁用所有 empty-result 源。

#### 耗时与诊断证据质量

- 所有请求累计耗时 `1,637,708 ms`，其中 Search 累计 `1,041,892 ms`；累计值受批量并发影响，不等于墙钟耗时。Search 中超过 1 秒 320 条、超过 5 秒 19 条、超过 10 秒 15 条、超过 20 秒 11 条，最大单步 32,291 ms。Detail/TOC/Content 的 p50 分别约为 203/219/202 ms，进一步说明 Search 是主要性能和稳定性问题。
- 2,859 条记录的 `responseWasDecoded` 均为 `false`；但其中 424 条带 `responseContentEncodings`，538 条带 response headers，710 条带 response snippet，2,142 条没有 response headers，另有 6 条缺少 finalURL、requestMethod、statusCode 或 decoded byte count 等核心字段。必须先核对这些字段的语义和填充时机，不能把 `responseWasDecoded=false` 直接解释成所有响应都未解码。
- 批量 runner 的阶段超时约为 10 秒，而 `SourcePipeline` 默认值为 20 秒；后续诊断报告必须同时记录“阶段实际 timeout policy”和“底层 pipeline 默认值”，避免把 runner 的主动截断误判成源端永久超时。

#### 根因处理策略

| 类别 | 处理策略 | 是否进入修复队列 |
| --- | --- | --- |
| `parsing` / `invalid-source` | 保留原始规则、失败阶段、输入摘要和桥接类型，进入兼容性修复队列 | 是，优先处理高频签名 |
| `network` / `timeout` / 5xx / connection lost | 记录可重试性、重试次数和最后一次失败时间，采用有限重试与观察隔离 | 条件进入，不直接禁用 |
| 403 / WAF / Cloudflare / `blocked` | 与普通网络失败分开，提供用户验证、WebView/浏览器降级或等待复测路径 | 否，进入人工/交互队列 |
| `empty-result` | 使用控制关键词、源类型和响应形状判断是无结果还是规则异常 | 待分类后决定 |
| API 业务参数/认证错误 | 记录缺失字段和响应业务码，交给规则编辑器或源配置修复 | 是，但与网络失败分开 |

#### 后续任务优先级

**P0：先解决会放大失败面的公共兼容问题**

- 统一 Search URL、POST 参数和相对 URL 归一化；把非法 URL 从普通 `network` 中独立出来，并保留 `finalURL`、request method、参数摘要和解析错误位置。
- 修复 Jsoup Element、Element collection 与字符串/字典之间的桥接类型保持，优先覆盖 `title.select`、`.attr`/`form.attr` 等高频调用。
- 为 `getWbiEnc`、JSON Parse EOF、常见全局 helper 建立本地 fixture 与 XCTest，不访问真实站点。
- 用 `www.linovel.net` 类型的脱敏/本地回放样本锁定 Search→Detail→TOC 链路；同时验证 `ruleToc.chapterList` 空值的错误定位。
- 将 403/WAF/Cloudflare/挑战页与普通 network failure 分成独立 failure classification，并在报告中给出不同下一步。

**P1：提高诊断结论的可解释性和批量稳定性**

- 把“关键词无结果”“规则解析为空”“参数失效”“API 业务错误”拆成可统计的子类；对 `empty-result` 增加控制关键词和源类型判断。
- 完善 404、5xx、timeout、connection lost 的有限重试、退避、隔离和复测队列，保留瞬时/永久失败置信度。
- 核查 `responseWasDecoded`、headers、snippet、decoded byte count 的采集时机，补齐缺失证据字段并为报告增加 evidence completeness。
- 评估批量诊断的 checkpoint、历史刷盘和内存占用，保留约 45 秒 checkpoint 和可恢复批次，避免长批次只在最后落盘。

**P2：把一次诊断结果变成可持续的健康度产品能力**

- 继续以 URL 作为身份，名称只做显示；增加健康状态时间衰减、`lastCheckedAt`、`nextRetestAt`、失败置信度和恢复队列。
- 按失败类型、源类型和阶段分组生成修复建议、暂时隔离建议和可恢复队列，避免“全绿/全禁用”二元决策。
- 将 991 源的批量报告接入规则编辑器、导出和历史对比；增加同一 source URL 的跨时间窗口趋势。
- 在真实 iOS Actions、Xcode/XCTest、真机和 Instruments 环境中验证 fixture、性能与证据字段；Windows 本地只保留静态检查和 Git 证据。

#### 本阶段边界与验收

- 这次数据只代表关键词 `重生`、一个约 17 分钟窗口和一次批量运行，不能推出源的永久健康状态，也不能替代二次复测。
- 当前环境未执行 Xcode build、XCTest、真机测试、Instruments 或二次真实网络验证；本阶段分析结果不得写成“已编译通过”或“真实设备已验收”。
- 阶段 2B 的代码验收必须补齐对应 fixture/XCTest、报告分类和证据完整度字段，然后按固定门槛执行 `git diff --check`、iOS build/test、unsigned IPA、`progress.md` 记录和可回滚点检查。

## 阶段 3：阅读器高级能力

- `AVSpeechSynthesizer` 朗读控制器。
- 播放/暂停/继续、语速、章节自动衔接、后台状态处理。
- 自动翻页、定时翻页、滚动自动阅读、睡眠定时器。
- 朗读、手势、翻页、进度持久化状态机解耦。

## 阶段 4：Flutter parity 与产品收尾

- 对齐缓存、主题、字体、翻页、更新检测、导入导出、空/错/加载状态。
- 补齐批量书源诊断和数据恢复。
- 做长列表、键盘、文件选择器、网络失败、重复点击等回归。
- 完成 release workflow、artifact 摘要和自签安装说明。

## 执行顺序锁定

1. 先收口当前 Actions（iOS build/test + unsigned IPA），不在失败未定位前扩大代码面。
2. 再做 RSS 完整化和书源测试闭环，保证内容链路可诊断、可缓存、可恢复。
3. 再做阅读器朗读/自动翻页的状态机和章节自动衔接。
4. 最后按 Flutter parity ledger 做产品收尾、回归矩阵和发布包装。

## 每阶段固定验收

1. `git diff --check`
2. Actions iOS build/test
3. Actions unsigned IPA
4. 失败时读取 annotations，修复后重新跑
5. 更新 `progress.md`
6. 回报提交、运行链接、artifact 和未验证项
