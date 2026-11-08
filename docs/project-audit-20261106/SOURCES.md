# 聚合书源审查与本批交接 · 2026-11-06

> 最新接续批次见文末「第二批交接」。上批 Discover 控件已由主代理接入；源变量仅会话内和发布页没有选择入口两项已在第二批实现，仍待新 SHA 原生 CI 验证。

## 已复核范围与证据

- 用户附件 `b58c112837e47d22873fab3fa95c0abf.json`：7,922 字节，SHA-256 `7fb823b473d92c6d08c0af2dc62efa58ceb045da04510f42bab99c92e6bd0939`，仅含一个 UXX 多类型聚合源。具有 JS 发现按钮、文本输入、源变量及 `book.type` 动态类型；不是普通静态分类表。
- `https://zq.vv9v.cn/index.html`：公开 HTML 发布目录，HTTP 200，45,615 字节，SHA-256 `431dc228a981dcc75977850a274963d1bc2c86567a2705fdf7d5d180ee66de20`。页面明示 `api/get_sources.php`，公开 JSON 返回 11 个下载条目，18,374 字节，SHA-256 `547ea7c021fca0fb088008c955d8baa25590726884526193598f0ba56935fb19`。
- UXX 小说关键词“三国”的公开搜索请求 HTTP 200，51,609 字节，SHA-256 `686692ccf2f336c349b4e7aabfa81995f2bc38340e50ed3d2d967f0139fc63b0`。这里只证明搜索响应可达，未把 HTTP 成功算成目录或正文通过。
- 原响应位于 `F:/SourceReadSwift/project-audit-20261106/sources`。没有访问 AI 网关、视频分片、付费内容或规避站点验证。
- 已检查导入链接/下载器、发现分类解析与 ViewModel、JS 模型桥、搜索/详情/目录/正文解析、引擎状态、SearchBook/BookDetail/书架持久化与阅读入口。不是全部源、全部功能已验收。

## 已修复的确定性缺口

| 缺口 | 决定性证据 | 本批修复 |
|---|---|---|
| 聚合源模式按钮消失 | 原 ExploreCategoryParser 将所有无 URL 条目当组标题，丢弃 action 和文本框 | 新 SourceExploreMenu 保留按钮、输入与默认值；链接分类与动作分开 |
| 发现选择与搜索状态不连续 | 原同步 parser 每次创建新 RulePersistentState，未使用 LegadoSourceEngine 的状态 | 新 exploreMenu/performExploreAction 使用同一源状态与请求上下文；阻塞 JS 在已有规则队列运行 |
| JavaScript 中 `::` 被误当静态分类 | 原静态解析先于 `@js:` 判定 | 先识别 JS，再解析其返回的数组 |
| 动态漫画被当小说 | JS 桥没有 `type`，搜索/详情/书架无每书类型；正文连 book 对象都未提供 | 新增兼容可选 mediaKind；保留每个结果自己的类型，贯通详情、书架恢复、目录与正文；仅对单书解析/路由派生 source 副本，原聚合源不改类型 |
| 附件切模式后搜索仍是小说 | exploreUrl 保存 `{"mode":"漫画"}`，searchUrl 却直接把整段 JSON 当字典 key | 独立修正版 `docs/sources/uxx-aggregate-compatible.json` 仅更改 searchUrl，兼容 JSON 和旧纯字符串变量；原附件不动 |

`BookSourceKind.legadoBookType` 的四值映射依据附件的显式 T 表（8/32/64/4）；不猜测未知位标志，未知值不产生媒体覆盖。未以修改 getVariable 返回语义来掩盖源配置问题。

## 界面接入点（主代理接续）

`ExploreViewModel` 已接入异步菜单、动作执行、源内搜索和迟到结果隔离。`DiscoverView.swift` 尚未修改。在分类区前加入：

```swift
ExploreSourceControls(
    controls: exploreViewModel.sourceControls,
    inputs: $exploreViewModel.sourceInputs,
    isLoading: exploreViewModel.isLoadingMenu,
    message: exploreViewModel.sourceActionMessage,
    onAction: exploreViewModel.performSourceAction
)
```

该组件只展示和回调，执行由 ViewModel 负责；按钮 44 pt，输入上方标签，加载期间禁用动作。分类折叠由主代理继续。未接入该组件前，不得宣布发现按钮已在界面可用。

## 验证

- 本地原 93 项测试通过。
- 新增 `scripts/test_aggregate_source_config.py` 的 4 项真实规则离线回放通过：四模式选择→搜索 URL、源内搜索输入、无 `uxt` 的章节依靠 book.type 获取两张漫画图片、旧变量兼容。使用 Node vm，限制执行时间，不访问网络。
- 新增 `AggregateSourceRegressionTests` 8 项 XCTest：发现控件、含双冒号的 JS、源状态共享与隔离、HTML/JSON 每行类型、完整长简介与详情类型、重启后正文上下文、旧 JSON 兼容。Windows 未运行，必须纳入 iOS 18 全量及 iOS 26 选定套件。
- Swift tree-sitter 对照接手前副本，已有 JSCoreRuntime/ExploreCategoryParser/SearchResultParser 的解析器误报未增加；新文件未发现 ERROR/missing 节点。这不是 SDK 类型检查。

```powershell
python -B -X utf8 -m unittest discover -s scripts -p 'test_aggregate_source_config.py'
python -B -X utf8 -m unittest discover -s scripts -p 'test_*.py'
git diff --check
```

## 未关闭事项与交付限制

- 发布目录不能作为书源 JSON 直接导入。已生成 `SOURCE-PUBLISHER-LINKS.json`，提供 11 个明确条目供选择。未做网站专用 API 抓取，也没有偷偷导入全部来源；应用内发布页链接选择仍需接续。
- 11 个发布源的搜索→详情→目录→正文尚未逐个真实跑通。无法据本批结论声称聚合源全部可用。验证页、登录/订阅及站点失效仍应分别报告。
- 源变量当前沿用现有引擎会话内持久状态；App 重启后的模式选择持久化未新增。书架每书媒体类型已落盘，旧 JSON 缺失新字段仍可读。
- 多媒体 `ReaderContentView` 的历史兜底入口、换源匹配对混合源的筛选及所有重建 SearchBook 的边缘路径仍需在全项目审查继续核对；本批覆盖主页书架与主详情的正常漫画入口。
- 小说/漫画实际动画、解码性能与设备帧率不属于本批通过结论。视频解析按用户要求留到下一轮。

## 回滚

改动前文件副本在 `F:/SourceReadSwift/project-audit-20261106/before/<仓库相对路径>`，仅按本批文件恢复；不要整体 reset 工作树。新增文件可在完成核对后单独移出。没有提交、推送或启动 CI。

## 第二批交接：发布目录、源变量与媒体边缘路径

### 改了什么

- `SourcePublisherLinks.swift`、`SourcePublisherLinksView.swift`、`SourceImportDownloader.swift`、`SourceStore.swift`、`SourceManagerView.swift`：HTML 不再一律报 JSON 错误。提取页面锚点、同源字面量 `fetch(url)` GET 引用及命名 JSON 链接目录，展示名称与完整地址，由用户逐项选择。不会执行网页脚本，不跟随带 options 的 fetch，不自动导入全部来源。最多 200 条、去重、拒绝 URL 内账号密码。已有现代/旧格式规则 JSON 继续交给书源解码器。远程纯链接列表进入选择界面；直接粘贴 JSON 仍沿用原导入行为。
- `SourceVariableStore.swift`、`RuleExecutionContext.swift`、`SourceEngine.swift`、`AppState.swift`：生产引擎显式注入 Keychain 存储，只持久化 `source.variable` 和 `source.variable.*`。因为部分源在这些字段存登录令牌，未使用明文 UserDefaults。256 KiB 上限；写失败保留本次会话状态并在发现操作后显示警告，读取损坏记录会发诊断并恢复空会话。章节临时变量、cookie 与 `java.put` 其他字段没有混入该存储。测试引擎默认不启用此存储。
- `BookSource.swift`、`DiscoverView.swift`：单书媒体类型优先于源的默认类型；发现明确 `book.type` 写入的聚合源进入媒体搜索候选。该检测只扩大候选，结果仍按实际媒体筛选，不擅自修改源模式。小说和漫画的同名同作者结果分组与行 ID 分离。
- `BookshelfReaderGatewayView.swift`、`BookDetailView.swift`：补齐慢路径/后台刷新/有声重建对象的媒体类型，换源缓存和新搜索按每书类型过滤，详情确认后再检查媒体类型并保存到书架。
- `GlobalSearchView.swift`：按已有 SettingsView 用法注入 `ReadingHistoryView(store: appState.readingHistoryStore)`，修复首轮 iOS 18/26 原生编译提供的 missing argument 红证据。
- 本批未改 ReaderView、WebScrollReaderView、ComicStripReaderView、主页设计和主题，也没有改 workflow、提交、推送或启动 CI。

### 验证与快照需求

实际执行：

```powershell
python -B -X utf8 -m unittest discover -s scripts -p 'test_*.py'
python -B -X utf8 scripts/check_source_followup.py
git diff --check
```

结果：101 项脚本测试通过；18 个本批 Swift 文件相对上一轮 CI 输入 `2b5e291e1bf284ee6120f404b39ab6aa2a04220c` 新增 tree-sitter ERROR/missing 为 0；差异检查通过。语法证据与文件哈希在 `SOURCE-FOLLOWUP-SYNTAX.json`。tree-sitter 不能证明类型检查通过。

新增 13 项 XCTest **未运行**，Windows 无 iOS SDK；主代理需以新 SHA 编译并执行：

| Suite | 本批新增 | 重点 |
|---|---:|---|
| SourcePublisherLinksTests | 4 | 相对地址、明确 GET 引用、跳过 POST/动态/跨域引用、导入协议、去重、上限、普通规则 JSON 不误判 |
| SourceVariablePersistenceTests | 6 | 新引擎恢复、源间隔离、临时字段排除、删除、过大值保护、损坏保存值、写失败与发现操作警告 |
| SourceImportDownloaderTests | 1 | 发布页下载→SourceStore 提供选择，尚未选中时没有导入任何源 |
| AggregateSourceRegressionTests | 2（累计 10） | 同名小说/漫画隔离和稳定 ID、媒体过滤、动态类型源候选 |

变量测试全部注入 `VariableMemorySecrets`，不会访问真实 Keychain。主代理的全局搜索等测试按原计划继续。iOS 26 选择列表应包含以上四个 suite；iOS 18 跑全量。新增生产文件为 **3 个**：`SourcePublisherLinks.swift`、`SourceVariableStore.swift`、`SourcePublisherLinksView.swift`；新增测试文件 2 个。XcodeGen 按现有目录规则纳入。

本批没有新增非 Swift 测试 fixture；此前 `docs/sources/uxx-aggregate-compatible.json` 与 `scripts/test_aggregate_source_config.py` 仍必须保留在快照。`SOURCE-PUBLISHER-LINKS.json` 为审计清单，不是硬编码的产品数据。

### 审查范围和未关闭项

`COVERAGE.json` 本批更新 18 个文件，逐个记录实际范围和内容哈希：9 个完整读取复核，9 个仅复核相关路径并标为 `partial`。其余文件维持原状态；没有把枚举文件或旧测试绿计作整文件审查。

- **真实网络链路尚未完成**：本批没有新增联网请求。先前 UXX 搜索 HTTP 200 仍只证明可达；详情/目录/正文以及 11 个发布条目逐源链路仍待主代理继续有限验收，不得宣称“聚合源全部可用”。有登录、共享令牌、验证和付费前提的来源应单独报告，视频和 AI 网关不在本轮请求范围。
- **发布页原生 UI 尚未验收**：实际断点、键盘、加载、空/错误及连续页面选择需 iOS 测试。通用提取只支持明确锚点与字面量 GET 引用；依赖动态 JS 构造地址的页面仍需用户复制实际 JSON 链接。
- **源变量后续生命周期**：目前源删除不会删除独立 Keychain 条目；重导同一源会恢复其设置。设置/数据管理的明确清除入口与备份策略尚未接入。复用的 `SecretStoring.value` 会把 Keychain 读取错误返回为 nil，因此只能辨认 JSON 损坏和写失败，无法区分首次未保存与设备钥匙串暂时不可读。未为此改动公共凭据接口。
- **媒体模式的能力边界**：动态类型候选检测仅识别明确的 `book.type =` / `book.setType(`，别名/间接脚本依然可能漏识别；不会替用户切换源自己的登录/发现模式。用户需要先选择该聚合源的模式，再搜索。
- **剩余媒体路径**：主页 `BookshelfView` 刷新对象构造仍需由主代理核对 `mediaKind`（遵守本批不改主页约束）；历史 ReaderContentView 兜底、下载恢复和其他所有 SearchBook 重建路径未全部审完。此批关闭正常 Gateway 慢路径/刷新及主详情重建入口。
- **全文件逐读未完成**：庞大的 SourceEngine、SourceStore、JSCoreRuntime，以及剩余 import/network/rule/JS 文件仍须按 COVERAGE pending/partial 接续；本批没有扩大到未知模块。

### 本批回滚

`scripts/check_source_followup.py` 已把上一轮 CI 输入中对应文件保存到 `F:/SourceReadSwift/project-audit-20261106/source-followup-before/<relative path>`，不会覆盖已有副本。回滚只恢复清单中 `baseline_exists: true` 的 13 个文件，并单独移出本批新增的 3 个生产文件、2 个测试文件；保留上批和主代理其他改动。不要对整个工作树 reset。运行脚本使用的是固定基线 `2b5e291...`，并非当前 HEAD。
