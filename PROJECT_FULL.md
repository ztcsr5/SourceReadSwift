# 纸间 SourceReadSwift · 项目全量文档

> **文档性质**：项目全量说明 + 版本工作记录 + 书源兼容性深度分析 + 验证与复现手册  
> **代码基线**：`v1.0.60`（Build 61）  
> **验证 Commit**：`66e83ea`（v1.0.60 代码 + 文档提交）；v1.0.30 的历史证据保留在 §八 / §九  
> **整理日期**：2026-10-27（主体整理于 2026-10-25）  
> **仓库**：`https://github.com/ztcsr5/SourceReadSwift`  
> **工作分支**：`codex/reader-feedback-fixes`（v1.0.59+）  
> **本地工作区**：`D:\Gemini反重力\SourceReadSwift2`

本文档回答四个问题：

1. 这个项目到底是什么、由哪些模块组成、每个功能落在哪个文件；
2. 书源解析能力现在做到哪一步，哪些是已实现、哪些是条件支持、哪些是明确边界；
3. 为什么 iOS 端的 Legado JSON 书源生态稀少，以及“完美兼容”为什么不是一个可交付的终点；
4. 从 v1.0.22 到 v1.0.60 做了什么；v1.0.30 的完整证据与 v1.0.60 的阅读界面重构分别是什么。

事实口径：**只把仓库内代码、XCTest、GitHub Actions 日志和本地产物写成“已完成”；未在真机或公网验证的内容明确标为“待验收”或 `NOT RUN`。** 不把“函数存在”当作“行为已验证”，不把“CI 编译通过”当作“真机体验通过”。

---

## 目录

- [一、项目定位与当前状态](#一项目定位与当前状态)
- [二、技术架构与核心数据流](#二技术架构与核心数据流)
- [三、仓库地图：目录、模块与文件清单](#三仓库地图目录模块与文件清单)
- [四、功能全量清单](#四功能全量清单)
- [五、书源解析引擎（核心能力）](#五书源解析引擎核心能力)
- [六、iOS 端 JSON 书源生态与“完美兼容”深度分析](#六ios-端-json-书源生态与完美兼容深度分析)
- [七、阅读器架构：四模式、跨章窗口与缓存](#七阅读器架构四模式跨章窗口与缓存)
- [八、版本演进：v1.0.22 → v1.0.30](#八版本演进v1022--v1030)
- [九、本轮 v1.0.30 工作全记录](#九本轮-v1030-工作全记录)
- [十、构建、发布与复现](#十构建发布与复现)
- [十一、已知边界、缺陷与后续路线](#十一已知边界缺陷与后续路线)
- [十二、文档索引与证据索引](#十二文档索引与证据索引)
- [十三、v1.0.60 阅读界面重构](#十三v1060-阅读界面重构2026-10-27)
- [附录 A：完整文件清单](#附录-a完整文件清单)
- [附录 B：术语与事实标记约定](#附录-b术语与事实标记约定)

---

## 一、项目定位与当前状态

### 1.1 这是什么

**纸间（SourceReadSwift）** 是一款原生 iOS 阅读器，核心能力是导入并执行 Android 开源阅读（Legado）格式的 **JSON 书源**，完成“搜索 → 详情 → 目录 → 正文 → 阅读”的完整链路，并在此基础上提供本地书籍、漫画、有声书、影视、RSS、TTS、WebDAV 与数据备份等阅读周边能力。

它不是对 Flutter 版本的继续修补，而是一次 **Swift 原生重写**：

- UI：SwiftUI，遵循 iOS 17 设计语言，最低支持 iOS 16；
- 排版：核心阅读区使用 UIKit TextKit 1，换取长文滚动与分页的精细控制；
- 书源运行时：JavaScriptCore + 自建 `java.*` / `org.jsoup.*` / `android.*` 兼容层；
- 网络：URLSession 为主，WKWebView 作为登录/验证/反爬兜底；
- 构建：XcodeGen 生成工程，GitHub Actions 在 macOS 上编译、测试、打出未签名 IPA。

### 1.2 当前基线（已核实）

| 项 | 值 |
|---|---|
| App 名称 | 纸间（InPage / SourceReadSwift） |
| Bundle ID | `com.edc21.SourceReadSwift` |
| 版本 | `1.0.30` |
| Build | `31` |
| 最低系统 | iOS 16.0 |
| Swift | 5.9 |
| 源码规模 | 170 个 Swift 文件 / 57,314 行（`SourceReadSwift/`，实测） |
| 测试规模 | 124 个 Swift 测试文件 / 18,995 行 / CI 987 个 XCTest |
| 书源能力样本 | 13 个真实源快照（`legado-capability-bank-20260908.json`，87,605 字节） |
| 最新 CI（代码） | iOS run `40112864505` / job `120928037334`，987 tests / 0 failures |
| 最新 CI（本文件） | iOS run `40121317778` / job `120953254683`，987 tests / 0 failures |
| 最新 IPA CI（本文件） | run `40121317766`，success |
| 最新 IPA | `C:\Users\Edc21\Desktop\SourceReadSwift-1.0.30-unsigned.ipa`，11,507,953 字节 |
| IPA SHA256 | `05F3EC27C1FD065D91289045229D0B25A2DCF4E5E5A1FCFCE86313624AA10261` |
| 回滚演练 | 独立副本 10/10 文件 SHA256 与基线一致 |

### 1.3 这个项目现在“能做什么”

按用户可见路径概括：

1. **导入书源**：JSON 文件、URL、阅读分享链接（`yuedu://` / `legado://`）、书源仓库、RSS/Atom、网页分享文本；
2. **搜索与发现**：单源/多源聚合搜索、发现页分类、详情页、目录、正文；
3. **阅读**：滑动、平移、覆盖、仿真四种模式；连续跨章前后翻；章级分页缓存；失败自动重试；字体/背景/字号/行距/边距/缩进/页脚高度等排版设置；书签；阅读统计；自动滚动；定时关闭；
4. **多媒介**：插图小说、漫画（缩放）、有声书（本地/云端/HTTP TTS）、影视解析；
5. **RSS**：源管理、文章列表、正文阅读、缓存、已读状态；
6. **书源工程**：规则编辑器、JSON 编辑器、登录/Cookie、全链路诊断、批量体检、健康度、报告导出（CSV/Markdown/JSON）；
7. **数据**：WebDAV 同步、完整数据导出/恢复、章节缓存、离线章节、阅读历史、书签、统计；
8. **Web 写源**：App 内起轻量 HTTP 服务，电脑浏览器写源/传源。

### 1.4 这个项目现在“不做什么”

明确边界，避免把边界当缺陷反复返工：

- **不提供、不存储任何网络图书内容**；书源由用户自行添加，版权归原站点与作者；
- **不伪造付费成功**：`payAction` 只执行书源声明的购买动作（打开购买页或执行源内 JS），不绕过真实支付；
- **不承诺 100% Legado 兼容**：兼容性是“能力矩阵 + 降级边界 + fixture 回归”，不是一次性完成的移植；
- **不支持 7z/RAR 解压**；ZIP/EPUB/GZIP 可用；
- **不伪造 Android 身份**：`androidId` 固定为兼容值，不声称是真机 Android ID；
- **不承诺无交互绕过 Cloudflare/验证码**：需要人工的站点必须走 WebView 登录/验证状态机；
- **不在本轮修改 UI**：用户上一轮提出的主页书架与阅读界面视觉问题已明确暂停，本文件只记录为待办，不声称已修。

### 1.5 版本与产物关系

```text
代码提交 91c9161  ──► iOS CI 40112864505（987 tests）──► IPA CI 40112864571 ──► 1.0.30 unsigned IPA
      │
      └──► 文档提交 594ed57 ──► 文档修正 5173230 ──► 本文件 75aeb44 ──► iOS CI 40121317778（987 tests）
                                                                  └──► IPA CI 40121317766
```

`594ed57` 触发的旧 run `40114078830` / `40114078838` 因推送 `5173230` 被并发组自动取消，属于正常行为，不是失败。

---

## 二、技术架构与核心数据流

### 2.1 技术栈

| 层 | 技术 | 说明 |
|---|---|---|
| UI | SwiftUI | 根 Tab、书架、发现、设置、阅读器外壳、弹层 |
| 长文排版 | UIKit / TextKit 1 | `NativeReaderTextView`，段落级布局、附件、异步重排 |
| 分页阅读 | SwiftUI + UIKit 混合 | TabView 平移、自定义覆盖手势、`UIPageViewController` 仿真 |
| 并发 | Swift Concurrency | `async/await`、`actor`、`Sendable`、任务 generation 令牌 |
| 书源 JS | JavaScriptCore | 同步 facade、`__nativeLegado` 等桥 |
| HTML 解析 | SwiftSoup | Jsoup 风格 CSS 选择器 + 自建指令 |
| JSONPath | 自研方言 | `JSONRuleExtractor`，面向 Legado 常见写法 |
| 压缩 | ZIPFoundation + libz | EPUB/ZIP/GZIP |
| 加密 | CryptoSwift + CryptoKit + Security | MD5/SHA/HMAC/AES/DES/3DES/RSA |
| 网络 | URLSession | 同步桥、Cookie、重定向、编码探测 |
| Web 兜底 | WKWebView | 登录、验证码、动态页面 |
| 构建 | XcodeGen | `project.yml` 单一配置源 |
| CI | GitHub Actions | `macos-15`，iOS 16 模拟器测试 + 未签名 IPA |

### 2.2 分层结构

```text
SourceReadSwift/
├── App/            应用入口、AppState、根 Tab、版本信息
├── Core/           与 UI 无关的领域层
│   ├── Engine/     书源执行引擎、付费动作、ZIP 书引擎
│   ├── Compression/ Zlib/GZIP 解压桥
│   ├── Rules/      规则解析：HTML/CSS、JSONPath、目录、正文、详情、搜索、诊断
│   ├── JavaScript/ JSCore 运行时、java.* 桥、编码、字体、模型桥
│   ├── Network/    请求构建、同步加载、编码解码、WebDAV、WebView 兜底
│   ├── Models/     书源、书籍、章节、书架、统计、合集
│   ├── Storage/    书源/书架/缓存/字体/内联图/历史/诊断/健康度
│   ├── Import/     本地 TXT/EPUB、第三方书源适配器
│   ├── Audio/      TTS 三引擎、有声书播放协调
│   ├── Reader/     智能网页正文抽取
│   ├── Security/   18+ 内容服务
│   ├── Verification/ 验证码协调器
│   └── Environment/ 沙盒、后台保活
├── Features/       面向用户的七个功能域
│   ├── Bookshelf/  书架与阅读入口
│   ├── Discover/   搜索、详情、目录、发现、Web 写源
│   ├── Reader/     四种阅读模式、设置、漫画、视频、音频、书签
│   ├── RSS/        RSS 阅读
│   ├── Settings/   设置、字体、TTS、Cookie、WebDAV、隐私
│   ├── SourceManager/ 书源管理、编辑、诊断、登录
│   └── Verification/ 验证码弹层
└── Shared/         设计系统、诊断、Foundation 扩展、导入、性能、分享
```

### 2.3 书源执行主链

```text
用户输入关键词
   │
   ▼
SearchURLResolver ──► SourceRequestBuilder ──► URLSession / WebView
   │                        │
   │                        ├─ Cookie / Header / POST body / 编码
   │                        ▼
   │                 ResponseTextDecoder（UTF-8/GBK/GB18030、ZIP/GZIP）
   │                        │
   ▼                        ▼
SourceEngine.search ──► SearchResultParser（HTML/CSS/XPath/JSONPath/JS）
   │                        │
   │                        ▼
   │                 SearchBook（名称/作者/封面/简介/字数/更新时间）
   ▼
BookDetailParser（ruleBookInfo）──► BookDetail（tocUrl/coverUrl/kind/status）
   │
   ▼
ChapterListParser（ruleToc + nextTocUrl 分页 + isVolume/formatJs/preUpdateJs）
   │
   ▼
ContentParser（ruleContent + nextContentUrl 分页 + title/payAction/imageStyle/imageDecode）
   │
   ▼
ChapterContent ──► ChapterContentCacheStore（内存 + 磁盘，500 章 LRU）
   │
   ▼
ReaderView（窗口 + 四模式 + 预取 + 重试 + 书签 + TTS）
```

### 2.4 阅读器数据流（v1.0.30）

```text
BookDetailView
   │ 打开书籍
   ▼
ReaderView
   ├─ ReaderChapterWindowPolicy：当前章 ± N 章
   ├─ ChapterContentCacheStore：先查缓存，命中即渲染
   ├─ queuePrefetch：近邻优先、串行请求缺失章
   ├─ 章级分页缓存：chapterPageLayoutSignature / chapterPageContentSignature
   ├─ 失败：ReaderChapterRetryPolicy（2/5/10 秒，3 次）
   └─ 读中：markRead → 移到 LRU 队首 + 刷新 cachedAt
        │
        ▼
四种阅读表面
   ├─ scroll      NativeReaderTextView（TextKit 1 扁平段落）
   ├─ pageTurn    TabView 原生分页（真实占位页跨章）
   ├─ cover       ReaderCoverSwipePolicy + 手势拖拽
   └─ pageCurl    PageCurlReaderView（UIPageViewController）
```

### 2.5 构建与发布链

```text
project.yml ──xcodegen──► SourceReadSwift.xcodeproj
                                   │
              ┌────────────────────┴────────────────────┐
              ▼                                         ▼
   iOS workflow（模拟器）                    Unsigned IPA workflow（真机）
   xcodebuild build                          xcodebuild -sdk iphoneos
   xcodebuild test（987 XCTest）              Package Payload/*.app → .ipa
              │                                         │
              └──────────────► GitHub Actions ◄─────────┘
                                   │
                                   ▼
                        产物 / 日志 / 版本断言
```

关键约束：

- 本机是 Windows，**没有 Xcode / swiftc / xcrun**，不能本地编译 iOS；
- 所有编译、测试、IPA 必须经 GitHub Actions；
- `project.yml` 是版本号唯一来源：`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`；
- CI 内用 `PlistBuddy` 断言 IPA 的版本、Build、Bundle ID、最低系统。

---

## 三、仓库地图：目录、模块与文件清单

### 3.1 顶层

| 路径 | 性质 | 说明 |
|---|---|---|
| `SourceReadSwift/` | 源码 | 170 个 Swift 文件，57,314 行 |
| `SourceReadSwiftTests/` | 测试 | 124 个 Swift 文件，18,995 行，987 个 XCTest |
| `docs/` | 文档 | 18 份根级文档 + `superpowers/` 规格与计划 + `ui-reference/` 参考图 |
| `project.yml` | 构建配置 | XcodeGen 单一配置源，版本 1.0.30 / Build 31 |
| `README.md` | 入口说明 | 项目目标、Windows 开发方式、阶段检查点 |
| `PROJECT_HANDOVER.md` | 交接备忘录 | v1.0.22 → v1.0.30 的实现细节与 CI 证据 |
| `PROJECT_FULL.md` | 本文档 | 全量项目说明 + 工作记录 + 深度分析 |
| `progress.md` | 历史进度 | 173 KB，早期阶段记录（只作历史参考） |
| `_apple-design-md.md` | 设计参考 | Apple 设计规范摘录 |
| `.github/workflows/` | CI | `ios.yml`、`unsigned-ipa.yml` |
| `build/`、`ci-log/` | 本地产物 | 构建/日志缓存，不属于源码 |
| `AppIcons_Candidates/` | 素材 | 图标候选 |

> README 中仍写着旧路径 `D:\Gemini反重力\SourceReadSwift`；当前真实工作区是 `D:\Gemini反重力\SourceReadSwift2`。以本文档与仓库实际路径为准。

### 3.2 App 层

| 文件 | 职责 |
|---|---|
| `App/SourceReadSwiftApp.swift` | `@main` 入口、环境注入、启动恢复 |
| `App/AppState.swift` | 全局依赖容器：书源、书架、缓存、RSS、诊断、Cookie、Web 写源、历史 |
| `App/RootTabView.swift` | 三 Tab（主页/发现/设置）、浮动玻璃 Tab Bar、有声书 mini player、验证码弹层 |
| `Shared/AppVersion.swift` | 版本展示的唯一封装 |
| `App/Info.plist` | Bundle 展示名、文件类型、ATS、本地网络说明 |
| `App/PrivacyInfo.xcprivacy` | 隐私清单 |

### 3.3 Core 层（13 个子域）

| 子目录 | 关键文件 | 职责 |
|---|---|---|
| `Compression/` | `ZlibBridge.h` | Zlib 解压桥接（GZIP） |
| `Engine/` | `SourceEngine.swift`、`SourcePipeline.swift`、`PayActionPolicy.swift`、`CryptoHelper.swift`、`ZlibraryEngine.swift` | 书源全链路执行、付费动作、加密辅助、ZIP 书引擎 |
| `Rules/` | `HtmlRuleExtractor.swift`、`JSONRuleExtractor.swift`、`ContentParser.swift`、`ChapterListParser.swift`、`BookDetailParser.swift`、`SearchResultParser.swift`、`SearchURLResolver.swift`、`PurifyRuleEvaluator.swift`、`InlineImageCodec.swift`、`ComicContentParser.swift`、`VideoContentParser.swift` | 规则解析与内容抽取 |
| `JavaScript/` | `JSCoreRuntime.swift`、`LegadoNativeBridges.swift`、`LegadoHostServices.swift`、`LegadoModelBridges.swift`、`LegadoCharset.swift`、`QueryTTF.swift`、`LegadoJavaScriptCompatibility.swift` | JSCore 运行时、`java.*` 桥、编码、字体映射 |
| `Network/` | `SourceRequestBuilder.swift`、`SynchronousSourceLoader.swift`、`SynchronousSourceNetworkBridge.swift`、`ResponseTextDecoder.swift`、`ResponseBodyDecoder.swift`、`SourceURLDirective.swift`、`SourcePaginationURLIdentity.swift`、`WebDAVSyncService.swift`、`WebViewFallback.swift` | 请求构建、同步桥、编码、分页 URL 身份、WebDAV、WebView 兜底 |
| `Models/` | `BookModels.swift`、`BookSource.swift`、`BookshelfModels.swift`、`ReadingStatsSummary.swift`、`SourceCollections.swift`、`BuiltinBrowserSourceProvider.swift` | 领域模型与内置源 |
| `Storage/` | `SourceStore.swift`、`BookshelfStore.swift`、`ChapterContentCacheStore.swift`、`ChapterDownloadStore.swift`、`InlineImageStore.swift`、`CustomFontManager.swift`、`PurifyRuleStore.swift`、`ReadingHistoryStore.swift`、`SourceCookieStore.swift`、`SourceHealthStore.swift`、`SourceDiagnosticHistoryStore.swift`、`RSS*Store.swift`、`AppDataBackup.swift` | 持久化与缓存 |
| `Import/` | `LocalTextBookParser.swift`、`LocalEPUBBookParser.swift`、`LocalTxtSmartDivider.swift`、`SourceImportDownloader.swift`、`SourceImportLinkParser.swift`、`HaiKuoShiJieSourceAdapter.swift`、`HuaHuoBookSourceAdapter.swift`、`XbsBookSourceAdapter.swift` | 本地书导入、书源导入适配 |
| `Audio/` | `ReaderTTSEngine.swift`、`CloudTTSClient.swift`、`CloudTTSPlayer.swift`、`CloudTTSProtocol.swift`、`HttpTTSClient.swift`、`AudioBookPlaybackCoordinator.swift`、`KeychainSecretStore.swift` | 三引擎 TTS、有声书播放 |
| `Reader/` | `SmartWebArticleExtractor.swift` | 网页正文智能抽取 |
| `Security/` | `B18PlusService.swift` | 18+ 内容服务 |
| `Verification/` | `VerificationCodeCoordinator.swift` | 验证码请求/提交/取消 |
| `Environment/` | `SandboxEnvironment.swift`、`BackgroundKeepAliveManager.swift` | 沙盒路径、后台保活 |

### 3.4 Features 层（七个功能域，34 个文件）

| 功能域 | 文件 |
|---|---|
| Bookshelf | `BookshelfView.swift`、`BookshelfReaderGatewayView.swift` |
| Discover | `DiscoverView.swift`、`BookDetailView.swift`、`ChapterListPresenter.swift`、`ExploreViewModel.swift`、`SearchBookRow.swift`、`SmartWebReaderView.swift`、`SourceWritingView.swift`、`LightweightHTTPMessage.swift` |
| Reader | `ReaderView.swift`、`NativeReaderTextView.swift`、`PageCurlReaderView.swift`、`ReaderChapterWindow.swift`、`ReaderPageLayoutEngine.swift`、`ReaderPagedNavigationPolicy.swift`、`ReaderPositionMapping.swift`、`ReaderSettingsModels.swift`、`ReaderImageStyle.swift`、`ReaderAutomationPolicy.swift`、`AudioBookPlayerView.swift`、`ComicReaderView.swift`、`VideoPlayerView.swift`、`QuoteCardView.swift` |
| RSS | `RSSArticlesView.swift`、`RSSArticleReaderView.swift`、`RSSReaderSettingsView.swift` |
| Settings | `SettingsView.swift`、`TTSSettingsView.swift`、`CustomFontManagementView.swift`、`CookieManagerView.swift`、`WebDAVSyncView.swift`、`ReaderDataManagementViews.swift`、`PrivacyLegalView.swift` |
| SourceManager | `SourceManagerView.swift`、`SourceRuleEditorView.swift`、`SourceLoginView.swift`、`SourceDiagnosticHistoryView.swift`、`RSSSourceEditorView.swift` |
| Verification | `VerificationCodeSheet.swift` |

### 3.5 Shared 层

| 目录 | 职责 |
|---|---|
| `DesignSystem/` | 主题、玻璃面板、远程图片加载/缓存、封面视图、Sakura 配色 |
| `Diagnostics/` | 诊断事件模型与展示 |
| `Foundation/` | 通用扩展、编码/字符串辅助 |
| `Import/` | 共享导入 UI 与文档类型 |
| `Performance/` | 性能采样、刷新率适配 |
| `HapticFeedback.swift` / `ShareSheet.swift` | 触感反馈、系统分享 |

### 3.6 测试与 fixture

- 124 个测试文件、18,995 行、987 个 XCTest（CI 实测）；
- 覆盖重点：JSONPath 60 例、HTML 规则 35 例、原生桥 34 例、源流程 34 例、书源存储 31 例、JSCore 25 例、书源模型 25 例、分页导航 22 例、自动化 19 例、付费动作 18 例、正文解析 17 例、目录元数据 16 例、跨章窗口 16 例；
- `SourceReadSwiftTests/Fixtures/`：
  - `legado-capability-bank-20260908.json`（13 源能力样本，87,605 字节）
  - `legado-stage29-matrix-source.json`（分页矩阵）
  - HTML/JSON/JS/JXNode/POST/Cookie/加密/动态 token/混合响应等 18 个小 fixture
  - stage29 的目录/详情/正文两页样本（用于跨页合并回归）

### 3.7 docs 目录

根级 18 份：

| 文档 | 用途 |
|---|---|
| `IOS-JSON-ECOSYSTEM-DEEP-DIVE.md` | iOS 生态与 12 个技术断层深度分析 |
| `JSON-IOS-COMPATIBILITY.md` | JSON 书源在 iOS 上的兼容性报告 |
| `SOURCE-CAPABILITY-MATRIX.md` | 13 源能力矩阵与字段实现状态 |
| `legado-js-compatibility-matrix.md` | JS/Java facade 兼容矩阵 |
| `legado-source-capability-table-20260908.md` | 单源能力明细表 |
| `source-rule-guide.md` | 书源规则编写指南 |
| `BUILD.md` | Windows + CI 构建说明 |
| `APP_STORE_READINESS.md` | 上架准备与审核边界 |
| `ui-reference-20260907.md` | UI 参考记录 |
| `2026-06-27-mr-function-absorption.md` | 功能吸收记录 |
| `stage-20b/28/29/31/32/33/34-acceptance.md` | 各阶段验收记录 |

子目录：

- `docs/superpowers/specs/`：10 份设计规格（Flutter 审计、Swift 重写、Legado JS 引擎、阅读器稳定性等）；
- `docs/superpowers/plans/`：1 份下一阶段计划；
- `docs/ui-reference/20260907/`：8 张 UI 参考图。

---

## 四、功能全量清单

> 状态口径：**已实现** = 有源码且至少有测试或 CI 证据；**条件支持** = 依赖站点/Cookie/登录/样本；**待验收** = 代码存在但缺真机或公网验证；**未实现** = 明确不做或尚未立项。

### 4.1 书架（主页）

| 功能 | 状态 | 实现/证据 |
|---|---|---|
| 书架列表与封面 | 已实现 | `BookshelfView.swift`、`AsyncBookCover` |
| 自定义分组 | 已实现 | `BookshelfStore.groups`、`BookshelfGroupPersistence` |
| 多媒介筛选 | 已实现 | 小说 / 漫画 / 有声 / 影视 / 本地 |
| 排序 | 已实现 | 最近阅读等 `BookshelfSortMode` |
| 本地书导入 | 已实现 | TXT / EPUB / 书源 JSON；`LocalTextBookParser`、`LocalEPUBBookParser` |
| 阅读进度 | 已实现 | `BookshelfStore` 持久化 |
| 阅读历史 | 已实现 | `ReadingHistoryStore`，移出书架仍保留 |
| 阅读统计 | 已实现 | `ReadingStatsSummary`，7 天趋势、目标、勋章、书架构成 |
| 全部书签 | 已实现 | `ReaderBookmarksView`、`BookshelfStore.bookmarks` |
| 离线章节 | 已实现 | `ChapterDownloadStore`、`OfflineChapterCacheView` |
| 更新提示 | 已实现 | 详情页刷新目录、最新章节 |
| 主页视觉风格 | **待办** | 用户已反馈“书架太奇怪”，本轮明确暂停，不做改动 |

### 4.2 发现与搜索

| 功能 | 状态 | 实现/证据 |
|---|---|---|
| 全网多源聚合搜索 | 已实现 | `DiscoverView` + `SourceEngine`，按启用源并发 |
| 搜索取消/清空 | 已实现 | `viewModel.cancelSearch/clearSearch` |
| 搜索历史 | 已实现 | `@AppStorage("discover_search_history")` |
| 热门推荐 | 已实现 | 搜索初始页 |
| 匹配模式 | 已实现 | `SearchMatchMode` |
| 结果过滤范围 | 已实现 | `SearchResultFilterScope` |
| 聚合结果按书聚合 | 已实现 | `AggregatedSearchBook`，展示多个书源 |
| 发现页分类 | 已实现 | `ExploreViewModel` + `ExploreCategoryParser` |
| 智能网页阅读 | 已实现 | `SmartWebReaderView` + `SmartWebArticleExtractor` |
| 搜索结果加入书架 | 已实现 | `pendingShelfAddBook` 确认弹层 |

### 4.3 详情与目录

| 功能 | 状态 | 实现/证据 |
|---|---|---|
| 书籍详情 | 已实现 | `BookDetailView`、`BookDetailParser` |
| 封面/简介/作者/分类/状态/字数/更新时间 | 已实现 | `BookDetail` 模型 |
| 目录加载与分页 | 已实现 | `ChapterListParser` + `nextTocUrl` |
| 卷标题 | 已实现 | `isVolume` → `volumeName` → `ChapterListPresenter.volumeHeader` |
| 目录 `formatJs` | 已实现 | 全量目录后执行，1-based index |
| 目录 `preUpdateJs` / `reverseToc` | 已实现 | TOC 请求前执行 |
| 章节字数/更新时间 | 已实现 | `metadataLabel`：`更新 <时间> · <字数>` |
| VIP/付费标记 | 已实现 | `isVip` / `isPay`，按钮条件 `hasLogin && isVip && isPay != true` |
| 标记已读 | 已实现 | 详情页菜单 |
| 刷新目录 | 已实现 | 详情页菜单 |
| 换源 | 已实现 | `availableSources` + `换源` 菜单 |
| 缓存后 50 章 / 全本缓存 | 已实现 | `ChapterDownloadStore`、批量缓存进度与停止 |
| 缓存前后章节 | 已实现 | 阅读器 `onCacheNextChapters` → `cacheAdjacentChaptersFromReader` |

### 4.4 阅读器

| 功能 | 状态 | 实现/证据 |
|---|---|---|
| 滑动模式 | 已实现 | `NativeReaderTextView`（TextKit 1） |
| 平移模式 | 已实现 | `TabView` 原生分页 + 真实占位页 |
| 覆盖模式 | 已实现 | `ReaderCoverSwipePolicy` + 拖拽手势 |
| 仿真模式 | 已实现 | `PageCurlReaderView`（`UIPageViewController`） |
| 连续跨章前后翻 | 已实现（真机待验收） | 双向窗口 + 占位页 + 预取，v1.0.28–v1.0.30 |
| 章级分页缓存 | 已实现 | `chapterPageLayoutSignature` / `chapterPageContentSignature` |
| 串行近邻预取 | 已实现 | `queuePrefetch`、`prefetchOrder`、generation 令牌 |
| 失败自动重试 | 已实现 | `ReaderChapterRetryPolicy`，2/5/10 秒，3 次 |
| 读即缓存（LRU） | 已实现 | `ChapterContentCacheStore.markRead`，上限 500 章 |
| 页脚章内页码 | 已实现 | `第 X / Y 章 · Z% · 页 a/b` |
| 滚动边界提示 | 已实现 | 距章尾 6 段 / 章首 3 段显示胶囊 |
| 字体 | 已实现 | 系统/细体/粗体/宋体/楷体/圆体/自定义 |
| 字号/行距/字距/段距/缩进/边距/标题间距/页脚高度 | 已实现 | `reader.*` AppStorage |
| 背景 | 已实现 | 纸/牛皮/豆沙绿/黛紫/青空/素白/浅灰/极黑/水墨/自定义 + 6 套 Sakura 主题 |
| 点击区域 | 已实现 | `ReaderTapAction` |
| 屏幕常亮/亮度 | 已实现 | `keepScreenAwake`、`readerBrightness` |
| 文本选择 | 已实现 | `textSelectionEnabled` |
| 书签 | 已实现 | 当前章书签、书签列表、跳转 |
| 金句卡片 | 已实现 | `QuoteCardView` |
| 自动滚屏 | 已实现 | `ReaderAutomationPolicy`，可调延迟 |
| 定时关闭 | 已实现 | `sleepTimerMinutes` |
| 朗读 | 已实现 | 阅读器内 TTS，跨章续播 |
| 刷新本章 | 已实现 | 阅读器菜单 |
| 购买本章 | 已实现（执行源声明动作） | `PayActionPolicy` |
| 缓存前后章节 | 已实现 | 阅读器菜单 |
| 书籍详情/换源 | 已实现 | 阅读器菜单 |
| 阅读设置面板 | 已实现 | 关闭按钮/背景点击/下滑关闭 |

### 4.5 漫画、插图与影视

| 功能 | 状态 | 实现/证据 |
|---|---|---|
| 插图小说 | 已实现 | `imageStyle` + `NSTextAttachment` + `ReaderIllustrationView` |
| 插图防盗链 | 已实现 | `SourceRequestBuilder.imageRequestHeaders`（Referer/UA） |
| 内联图解码 | 已实现 | `imageDecode` 四类负载 → `srdata://` → `UIImage` |
| 内联图去重/裁剪 | 已实现 | `InlineImageStore`，SHA256 去重，256 MB 上限 |
| 漫画条漫/翻页 | 已实现 | `ComicReaderView` |
| 漫画双指缩放 | 已实现 | 1×–3.5× |
| 漫画放大后平移 | **未实现** | 仅有缩放，无 pan；TabView 手势冲突待真机调阈值 |
| 影视解析 | 已实现 | `VideoContentParser`、`VideoPlayerView` |
| 手势调光/调音/倍速/选集 | 已实现 | `VideoPlayerView` |

### 4.6 有声书与 TTS

| 功能 | 状态 | 实现/证据 |
|---|---|---|
| 本地 TTS | 已实现 | `AVSpeechSynthesizer`，`TTSEngineKind.local` |
| 讯飞云端 TTS | 已实现 | `CloudTTSClient` / `CloudTTSPlayer`，WebSocket 协议 |
| HTTP TTS | 已实现 | `HttpTTSClient`，兼容 Legado `httpTTS` 模板 `{{java.encodeURI(...)}}` |
| 云端凭据 | 已实现 | `KeychainSecretStore` 存 Keychain，不落明文 |
| 有声书播放 | 已实现 | `AudioBookPlaybackCoordinator` |
| 后台/锁屏播放 | 已实现 | 后台音频会话 |
| 定时暂停/倍速 | 已实现 | 播放器 UI + 协调器 |
| 全局 mini player | 已实现 | `RootTabView` Tab 上方 |
| 跨章续播 | 已实现 | 窗口命中原位续播，缺章 pending 后恢复 |

### 4.7 RSS

| 功能 | 状态 | 实现/证据 |
|---|---|---|
| RSS/Atom 源导入 | 已实现 | `SourceImportLinkParser`、`RSSFeedParser` |
| RSS 源管理 | 已实现 | `RSSSourceEditorView` |
| 文章列表 | 已实现 | `RSSArticlesView` |
| 文章阅读 | 已实现 | `RSSArticleReaderView` |
| 已读状态 | 已实现 | `RSSArticleStateStore` |
| 正文缓存 | 已实现 | `RSSArticleContentCacheStore` |
| Feed 缓存 | 已实现 | `RSSFeedCacheStore` |
| RSS 阅读设置 | 已实现 | `RSSReaderSettingsView` |

### 4.8 书源管理

| 功能 | 状态 | 实现/证据 |
|---|---|---|
| JSON 文件导入 | 已实现 | `SourceStore.importJSONData` |
| URL 导入 | 已实现 | `SourceImportDownloader` |
| 分享链接导入 | 已实现 | `yuedu://` / `legado://`，`SourceImportLinkParser` |
| 书源仓库 | 已实现 | 仓库 JSON、批量导入、去重 |
| 剪贴板导入 | 已实现 | 自动识别 JSON/URL/分享文本 |
| 第三方适配 | 已实现 | 海阔视界、花火、XBS 适配器 |
| 书源列表/启用/禁用/删除 | 已实现 | `SourceManagerView` |
| 规则编辑器 | 已实现 | `SourceRuleEditorView` |
| JSON 编辑器 | 已实现 | 原文编辑，按 `bookSourceUrl` 覆盖 |
| 书源登录 | 已实现 | `SourceLoginView` + WKWebView |
| Cookie 管理 | 已实现 | `SourceCookieStore`、`CookieManagerView` |
| 全链路诊断 | 已实现 | 搜索→详情→目录→正文，步骤请求/响应/耗时 |
| 批量体检 | 已实现 | `SourceBatchCheckCoordinator`，并发、可后台、可停止 |
| 健康度 | 已实现 | `SourceHealthStore` |
| 诊断历史 | 已实现 | `SourceDiagnosticHistoryStore` |
| 修复建议 | 已实现 | `SourceDiagnosticRepairAdvisor` |
| 报告导出 | 已实现 | CSV / Markdown / JSON / 精简看板 |
| Web 写源 | 已实现 | `SourceWritingView` + `LightweightHTTPServer` |
| 规则预览 | 已实现 | `RulePreviewEvaluator` |
| 规则校验 | 已实现 | `RuleEditorValidator` |

### 4.9 数据、同步与备份

| 功能 | 状态 | 实现/证据 |
|---|---|---|
| WebDAV 同步 | 已实现 | `WebDAVSyncService`、`WebDAVSyncView` |
| 完整数据导出 | 已实现 | `AppDataBackup`、`AppDataBackupDocument` |
| 完整数据恢复 | 已实现 | `restoreAppDataBackup` |
| 阅读偏好恢复 | 已实现 | `restoreReaderPreferences` |
| 章节缓存清理 | 已实现 | 设置页 |
| RSS 缓存清理 | 已实现 | 设置页 |
| 自定义字体导入 | 已实现 | `CustomFontManager` |
| 隐私与条款 | 已实现 | `PrivacyLegalView` |

### 4.10 设置与关于

| 功能 | 状态 |
|---|---|
| 主题（跟随系统/浅色/深色） | 已实现 |
| 字体管理与自定义导入 | 已实现 |
| 朗读引擎与云端凭据 | 已实现 |
| 书源管理 / Web 写源 / 规则体检 / 净化规则 | 已实现 |
| 清理章节缓存 / RSS 缓存 | 已实现 |
| 阅读历史 / 阅读统计 / 全部书签 / 离线章节 | 已实现 |
| 会话与 Cookie 管理 | 已实现 |
| WebDAV 同步 / 导出 / 恢复 | 已实现 |
| 最近诊断 | 已实现 |
| 关于纸间 | 已实现 |

---

## 五、书源解析引擎（核心能力）

### 5.1 执行链与阶段

书源执行由 `SourceEngine` 驱动，五个阶段：

```text
search   → 关键词 → searchUrl → ruleSearch → [SearchBook]
detail   → bookUrl → ruleBookInfo → [BookDetail]
toc      → tocUrl → ruleToc（可多页）→ [BookChapter]
content  → chapterUrl → ruleContent（可多页）→ [ChapterContent]
explore  → exploreUrl → 分类 → 搜索结果
```

每个阶段都有：

- 请求构建（method/header/body/charset/URL 指令）；
- 响应解码（文本/字节/压缩/编码）；
- 规则求值（HTML/CSS/XPath、JSONPath、JS、默认规则）；
- 结果模型与诊断事件；
- 失败时的 stage、规则字段、输入摘要、期望/实际。

### 5.2 规则层能力

| 能力 | 实现 | 说明 |
|---|---|---|
| HTML/CSS 选择器 | `HtmlRuleExtractor` | Jsoup 风格，支持 `@text`、`@html`、`@abs:`、`@textNodes` 等指令 |
| XPath | `XPathRuleTranslator` | 常用路径转 CSS/原生求值 |
| JSONPath | `JSONRuleExtractor` | 自研方言，见 5.3 |
| JS 规则 | `JSCoreRuntime` | `@js:`、`<js>`、`{{...}}` 模板 |
| 默认规则 | `LegadoDefaultRuleTranslator` | 空规则时的通用抽取 |
| 规则组合 | `RuleOperatorSplitter`、`RuleTransformParser` | `##`、`\|\|`、`&&`、`%%` 转换链 |
| URL 指令 | `SourceURLDirective` | `@js:`、`@put`、`@get`、`{{}}`、相对 URL |
| 分页 | `SourcePaginationURLIdentity`、`ChapterListParser`、`ContentParser` | `nextTocUrl` / `nextContentUrl`，按 URL 身份去重 |
| 净化 | `PurifyRuleEvaluator` | 正则替换、广告/尾巴清理，按顺序执行 |
| 预览 | `RulePreviewEvaluator` | 编辑器中即时验证规则 |

### 5.3 JSONPath 方言：已实现与明确差异

已实现（`JSONRuleExtractorTests` 60 例）：

| 能力 | 形式 |
|---|---|
| 根/成员 | `$.data.list`、`data.list` |
| 递归下降 | `$..name` |
| 通配 | `$[*]`、`$.*` |
| 索引 | `$[0]`、`$[-1]` |
| 切片 | `$[start:end]`、`$[start:end:step]`，支持负值 |
| 联合 | `$['a','b']`、`$[0,2]`，去重保序 |
| 过滤器 | `$[?(@.x == 1)]`，支持 `=~ == = != > < >= <=` |
| 集合谓词 | `in`、`nin`、`subsetof`、`anyof`、`noneof`、`contains`、`size`、`empty`、`exists` |
| 函数 | `length/size/count/value/match/search/keys/first/last/min/max/sum/avg/concat/append/index` |
| 指令 | `@json:` 自动解码 |
| 特殊 key | `$['a-b']` |
| 转换链 | `##regex##replacement`、`\|\|`、`&&`、`%%` |

明确差异（必须用 fixture 验证，不能假设）：

1. 不是完整 Jayway JsonPath；
2. 属性查找大小写敏感（有测试锁定）；
3. 数组上的 bare member step 会自动 map，属于贴近 Legado 的扩展；
4. 对象过滤器只保留 value 为 object 的条目并按 key 排序；
5. 转换链是项目规则层，不是 JSONPath 标准。

### 5.4 JavaScriptCore 运行时能力

`JSCoreRuntime` 注入 `__nativeLegado`、`__nativeRule`、`__nativeJsoup`、`__nativeJXNode` 等桥。

| 类别 | 已接入（有 XCTest 或 fixture） |
|---|---|
| 网络 | `java.ajax/get/post/fetch/connect/ajaxAll/head`；状态码、header、bytes、final URL；`URLConnection` 属性/流 |
| 解析 | `java.getString/getStringList/getElements`；CSS/XPath/JSONPath；Jsoup/JXNode |
| DOM | `org.jsoup.Jsoup`、JXNode、元素/属性/兄弟节点链 |
| 存储 | `java.put/get/remove/getStr/putJson/getJson` |
| 编码 | Base64、Hex、字节数组、charset-aware String bytes |
| 哈希 | MD5、SHA、RIPEMD160、HMAC |
| 对称加密 | AES、DES、3DES、`createSymmetricCrypto` |
| 非对称/签名 | RSA（PEM/DER/base64）、`createAsymmetricCrypto`、`createSign` |
| Java facade | `StringBuilder`、`HashMap`、`ArrayList`、`Pattern/Matcher`、`URL/URI` |
| Android facade | `Build`、`TextUtils`、`Base64` |
| 模型 | source/book/chapter getter、变量 map、`isVip`、`isPay` |
| 付费 | `payAction` 的 `isTrue`、`@js:`、`<js>`、纯 URL 短路 |
| 字体 | `QueryTTF` 字体 cmap 映射 |
| Cookie | 源级 CookieJar、请求头合并 |

设计约束：

- JavaScriptCore 回调是**同步**的；外部网络通过 `RuleExecutionContext` 注入；
- 文件/ZIP 访问限制在 `Documents/LegadoSandbox`；
- 未实现的 `java.*` 不抛 TypeError，而是 Proxy 降级为可诊断空值（`bridge.error java.<name>`）；
- 不伪造登录、验证码、付费成功。

### 5.5 编码、压缩、加密、图片

| 能力 | 状态 | 说明 |
|---|---|---|
| UTF-8 / GBK / GB18030 | 已实现 | `ResponseTextDecoder`、`LegadoCharset` |
| BOM / header 错标 / 混合编码 | 条件支持 | 有解码策略，仍需真实源 fixture |
| ZIP / EPUB | 已实现 | ZIPFoundation |
| GZIP | 已实现 | libz 桥 |
| 7z / RAR | **不支持** | 导入时提示 ZIP/预解压，不在运行时静默空值 |
| AES / DES / 3DES / RSA / HMAC | 已实现 | CryptoSwift + CryptoKit + Security |
| SM4 / GOST / 自定义 KDF | **未覆盖** | 遇到需新增桥与 fixture |
| 字体反爬 | 已实现（常见 cmap） | `QueryTTF`；加密字体/复杂 cmap 仍需样本 |
| 图片 URL 重写 | 已实现 | `imageStyle` + 防盗链 Header |
| `imageDecode` 四类负载 | 已实现 | data URI、裸 base64、`byte[]` JSON 数组、数字键对象 |
| 多切片 Canvas 拼图 | **未实现** | 缺真实切片样本，禁止猜测坐标系 |
| 32 MB 负载上限 | 已实现 | `InlineImageCodec` |
| `srdata://` 注册表 | 已实现 | SHA256 去重、256 MB 裁剪、排除 iCloud 备份 |

### 5.6 目录与正文扩展字段状态

| 字段 | 状态 | 证据 |
|---|---|---|
| `ruleToc.chapterList/chapterName/chapterUrl` | 已实现 | `ChapterListParser` |
| `nextTocUrl`（单值/数组/文本） | 已实现 | 分页身份去重 + 多页合并 |
| `isVolume` | 已实现 | HTML/JSON 两条链，卷行消费为 `volumeName` |
| `formatJs` | 已实现 | 全量目录后执行，1-based，单章失败回退 |
| `preUpdateJs` | 已实现 | TOC 请求前执行，支持 `book.setReverseToc` |
| `reverseToc` | 已实现 | 反转章节列表 |
| `isVip` / `isPay` | 已实现 | 独立解析，未知为 nil |
| `wordCount` / `updateTime` | 已实现 | 目录副标题 + 详情 |
| `ruleContent.title` | 已实现 | HTML/JSON 响应求值，空值回退目录标题 |
| `ruleContent.imageStyle` | 已实现 | DEFAULT/FULL/TEXT/SINGLE |
| `ruleContent.imageDecode` | 已实现（四类） | 内联图管线 |
| `ruleContent.payAction` | 已实现 | URL/模板/JS，`isTrue` 分类，购后缓存失效 |
| `ruleContent.nextContentUrl` | 条件支持 | 单 URL/分页链可用；多值合并语义待 fixture 固定 |
| `ruleContent.replaceRegex` | 条件支持 | 已执行；跨页合并顺序待固定，单 URL 源零回归 |
| `ruleBookInfo.downloadUrls` | **未消费** | 不解析、不渲染入口，避免死按钮 |
| `sourceRegex` | 待验证 | 是否进入正文元数据链需具体源证据 |

### 5.7 条件支持与明确边界

| 项 | 现状 | 处理原则 |
|---|---|---|
| Cookie / 登录态 | 条件支持 | `enabledCookieJar`、`SourceLoginView`、Cookie 管理 |
| POST 搜索 | 条件支持 | 7/13 样本声明，body 模板与编码已接 |
| 动态 token | 条件支持 | `@js:` / 变量 / 首页取 token，fixture 覆盖 |
| 验证码 | 部分支持 | `VerificationCodeCoordinator` + 弹层；`startBrowserAwait` 仍缺完整 UI 状态机 |
| WebView DOM 脚本 | **不支持在 DOM 内执行** | 规则在 JSCore 求值；WebView 只做登录/验证/兜底 |
| `androidId` | **固定值** | 不伪造真机身份 |
| Promise | **同步 facade** | JS 侧 Promise 不是真正异步 |
| Cloudflare / TLS 指纹 | **不稳定** | 需 WebView 或明确提示人工 |
| 任意 Java 类 / `importClass` / `Packages` | **不完整** | 常用 facade + 未实现调用诊断 |
| 后台长时批量抓取 | **受限** | iOS 后台模型限制，需前台/保活策略 |

### 5.8 诊断体系

书源诊断不是“打印一行错误”，而是结构化报告：

```text
SourceDiagnosticReport
├── 每个 stage：search / detail / toc / content / explore
├── 每步：request（method/URL/headers/body）、response（HTTP/解码）、耗时
├── 结果数量、失败原因、规则字段
├── SourceDiagnosticEvidence：可复制的证据片段
├── SourceDiagnosticClassifier：错误分类
├── SourceDiagnosticRepairAdvisor：修复建议 + 定位字段
└── SourceDiagnosticReportExporter：CSV / Markdown / JSON / 精简看板
```

配套：

- `SourceBatchCheckCoordinator`：批量体检，并发、后台持续、可停止、进度；
- `SourceHealthStore`：健康状态与最后检测时间；
- `SourceDiagnosticHistoryStore`：最近诊断历史；
- `SourceManagerView` 的“可视化链路”：逐阶段请求/响应展开；
- 失败时提供“编辑规则 / 编辑 JSON / 运行全链路测试”。

### 5.9 测试与 fixture 规模

| 测试文件 | 用例数 | 覆盖 |
|---|---:|---|
| `JSONRuleExtractorTests` | 60 | JSONPath 方言、过滤器、函数、转换链 |
| `HtmlRuleExtractorTests` | 35 | CSS/XPath、指令、属性、文本节点 |
| `LegadoNativeBridgeTests` | 34 | `java.*` 网络/解析/加密/集合 |
| `SourceFlowEngineTests` | 34 | 搜索→详情→目录→正文主链 |
| `SourceStoreTests` | 31 | 导入/导出/去重/仓库 |
| `JSCoreRuntimeTests` | 25 | JS 运行时、降级诊断、模型桥 |
| `BookSourceTests` | 25 | 书源模型与 Codable |
| `ReaderPagedNavigationPolicyTests` | 22 | 分页边界、章界 |
| `ReaderAutomationPolicyTests` | 19 | 自动滚动/朗读策略 |
| `PayActionTests` | 18 | 付费动作求值与分类 |
| `ContentParserTests` | 17 | 正文、标题、图片、净化 |
| `ChapterListMetadataTests` | 16 | 卷/字数/付费/formatJs |
| `ReaderChapterWindowPolicyTests` | 16 | 窗口、预取、占位、upperBound |
| `SourceEngineCLevelFixtureTests` | 7 | C 级复杂源离线样本 |
| `LegadoStage25CompatibilityTests` | 7 | 字体/加密/跨阶段 |
| `LegadoAdvancedJsonSourceTests` | 6 | 高级 JSON 源 |
| `SourceEngineLegadoCorpusTests` | 5 | 13 源能力库端到端 |
| `LegadoCapabilityBankTests` | 2 | 能力库结构校验 |

> 总数以 CI 的 987 为准；上表是重点文件，不是全部 124 个测试文件。

### 5.10 书源能力结论

**能稳定跑通的**：标准 HTML/CSS 源、JSON API 源、常见 JS 规则、POST 搜索、GBK 站点、Cookie 会话、目录/正文分页、卷目录、字数/更新时间、VIP 标记、插图与内联图、付费动作声明。

**需要样本才能继续的**：多切片图片、复杂字体 cmap、`nextContentUrl` 多值、`replaceRegex` 跨页顺序、`sourceRegex`、SM4/GOST、强反爬。

**不能承诺的**：100% Jayway JSONPath、完整 Rhino 语义、任意 Java/Android API、无交互 Cloudflare、7z/RAR、真实 Android ID。

---

## 六、iOS 端 JSON 书源生态与“完美兼容”深度分析

> 本章回答两个问题：
> 1. 为什么市面上 iOS 的 JSON 书源软件这么少（源阅读等还未开源）？
> 2. JSON 书源想在 iOS 上“完美兼容”为什么难？
>
> 生态数字是 2026-10-24 的 GitHub 快照，只用于说明量级，不代表项目质量或许可可用性。

### 6.1 问题一的直接回答：不是“没有”，而是“少、分散、深度参差、上架困难”

截至 2026-10-24，GitHub 上确实存在多个 iOS/macOS 的 Legado 兼容项目：

| 仓库 | Stars | 技术栈 | 许可 | 观察 |
|---|---:|---|---|---|
| `Kequans/legado-for-mac-pub` | 68 | Swift/SwiftUI | 公开仓库 | macOS 版，不是 iOS |
| `Aminark/legado-ios`（小浣熊阅读） | 53 | Swift/SwiftUI | GPL-3.0 | iOS 15+，侧载 IPA，明确不提供书源 |
| `FactorCitrus/Legado-iOS`（橘阅） | 20 | Swift/SwiftUI | GPL-3.0 | 声明兼容 Legado 3.0 与 WebDAV |
| `bennytsai1234/Night-Reader` | 16 | Dart/Flutter | GPL-3.0 | Android 为主，README 明确 iOS 版未在 iPhone 实测 |
| `tomcat117853/LegadoReader-iOS` | 9 | Swift | 公开仓库 | 小型实现 |
| `zhong228/ShuYue`（书悦） | 8 | Swift | 公开仓库 | 声明兼容 Legado/阅读 3.0 |
| `ztcsr5/SourceReadSwift`（本项目） | 0 | Swift/SwiftUI | 当前仓库 | 自建兼容层与 fixture |

三个结论：

1. **生态存在，但规模远小于 Android**：头部项目只有几十 stars，和 Legado Android 主仓库不在一个量级；
2. **分发以侧载为主**：小浣熊阅读明确写“没有付费 iOS 开发者账号，暂不上架 App Store”，提供 IPA + 自签/TrollStore；Night-Reader 的 iOS 版也是未签名 IPA。原因不是单纯“技术不行”，而是 App Store 审核、数字内容/IAP、第三方书源版权风险共同作用；
3. **闭源产品无法复用**：源阅读等没有源码，只能做行为观察，不能复用它的 Java/JS 桥、Cookie 管理、WebView 登录或图片解码管线；每一个兼容点都要自建，成本被显著抬高。

### 6.2 四个真实约束

#### 6.2.1 分发与审核约束

- App Store 审核指南 2.5.2 要求 App 自包含、不得下载并执行改变 App 功能的代码；4.7 对 HTML5 小程序/游戏有额外条件；5.2.2 涉及第三方知识产权；3.1.1 要求数字内容使用 IAP。书源阅读器天然接近这些边界。
- 结果：多数项目选择 IPA 侧载、AltStore/Sideloadly、TrollStore 或自签；免费账号 7 天过期，劝退普通用户，也让开发者缺少稳定收入。

#### 6.2.2 内容与版权约束

- 书源指向的站点内容版权归属复杂；App 本身不提供内容，但“可导入任意源”容易被审核视为协助访问未授权内容。
- 结果：产品必须明确“本地阅读与书源解析工具”的定位，不做内容分发、不做付费墙绕过。

#### 6.2.3 经济与维护约束

- 书源站点经常改版、加验证、换加密、换域名；兼容层需要持续维护。
- iOS 开发者数量、侧载意愿、付费意愿都小于 Android；一个几十 stars 的项目很难支撑全职维护。
- GPL-3.0 项目之间不能随意闭源复用；参考其行为可以，复制代码会触发许可义务。

#### 6.2.4 工程约束

Android 侧有现成 Java/Rhino/OkHttp/Jsoup/Android WebView；iOS 侧需要从零搭：

- `java.*` 的 Swift facade；
- 同步网络桥（JSCore 内 `java.ajax` 必须“看起来同步”）；
- SwiftSoup 替代 Jsoup；
- 自研 JSONPath 方言；
- WKWebView 登录/验证码状态机；
- CoreText/CoreGraphics 字体与图片管线；
- iOS 沙盒下的文件、下载、后台任务。

这不是“写一个 JSON 解析器”能覆盖的，任何一个环节都可能成为某个书源的硬阻塞。

### 6.3 问题二的直接回答：Legado 书源不是静态 JSON，而是组合协议

Legado 书源实际是：

```text
JSON 配置
  + Rhino JavaScript
  + Java / Android 宿主 API
  + Jsoup / CSS / XPath
  + Jayway JSONPath
  + OkHttp
  + Android WebView
  + Android 文件 / 字体 / 图片能力
```

iOS 没有 Android Runtime，也没有 Rhino；JavaScriptCore 只提供 JS 语言本身，`java.*`、`android.*`、`importClass`、`Packages`、`load` 全部要由 Swift 重新实现。每多一个宿主 API，就多一个兼容面；书源作者可以任意组合这些 API，所以这是一个**开放集合**，不存在“写完某一天就 100%”的终点。

更准确的目标不是“完美兼容”，而是：

> **可验证的能力矩阵 + 明确的降级边界 + 可诊断的失败原因 + 可持续的 fixture 回归。**

### 6.4 12 个技术断层

| # | 断层 | Legado/Android | iOS 现实 | 本项目现状 |
|---:|---|---|---|---|
| 1 | JS 引擎 | Rhino，含 `java.*`、`importClass`、`Packages`、`load` | JavaScriptCore，只有标准 JS + 自建 bridge | 已注入 `java`/`source`/`book`/`chapter`/`cookie`/`cache` 等 facade；仍是开放集合 |
| 2 | Java/Android API | 任意 Java 类、`android.*`、`Context`、`SharedPreferences` | 无 JVM、无 Android Runtime | 常用 API 已桥接；未实现调用显式诊断 |
| 3 | DOM/CSS | Jsoup + 扩展伪选择器 | SwiftSoup，选择器/行为不完全一致 | `HtmlRuleExtractor` 自建 `@textNodes`/`@abs:` 等处理；持续补 fixture |
| 4 | JSONPath | Jayway JsonPath | 自研方言子集 | 已覆盖常见路径/过滤/函数；不是完整 Jayway |
| 5 | 正则 | Java `Pattern` | `NSRegularExpression` | `\Q...\E`、占有量词、命名组、Unicode 属性存在差异 |
| 6 | 网络栈 | OkHttp，连接池/拦截器/TLS 指纹 | URLSession | 重定向、Cookie、TLS/HTTP2 指纹不同；Cloudflare 需 WebView |
| 7 | JS 内同步网络 | Rhino 阻塞调用 | JSCore 同步桥 | 已实现；需防死锁、超时、主线程阻塞 |
| 8 | 编码 | Java Charset，GBK/GB18030/Big5 | `String.Encoding` / CFString | 已有解码器；错标 header、BOM、混合编码仍需 fixture |
| 9 | 加密 | JCE 全量 Provider | CryptoKit/CommonCrypto + 自建 | 常见 AES/DES/3DES/RSA/HMAC 已桥接；SM4/GOST/自定义 KDF 未覆盖 |
| 10 | 图片 | `imageDecode` 可返回 `byte[]`/Bitmap，切片拼图 | Data → UIImage/CGImage | URL 重写与四类字节负载已实现；字节级切片拼图是明确缺口 |
| 11 | 字体 | Android Typeface/TTF cmap | CoreText | `QueryTTF` 已做映射；加密字体/复杂 cmap 仍需补 |
| 12 | 文件/后台 | 任意路径、`un7z`、长时间后台 | App Sandbox、后台任务受限 | ZIP/EPUB 可用；RAR/7z、任意路径、长时批量下载需降级设计 |

三个经常被低估的差异：

- **Rhino 的 JS 语义不是 JavaScriptCore**：`Java.type`、`importClass`、`Packages`、`load`、Rhino 的 `String` 扩展、`java.lang` 自动装箱都不是标准 ECMAScript；
- **书源作者按 Android 调试**：他们看的是 Legado Debug 日志和 Android 行为；iOS 端必须输出同等粒度的诊断，否则只能猜；
- **站点反爬在演进**：TLS 指纹、HTTP/2 指纹、Cloudflare Turnstile、验证码、字体混淆、图片切片，任何一项都可能让“昨天能用的源”今天失效。

### 6.5 兼容等级：把“完美”拆成可验收的层级

| 等级 | 定义 | 验收方式 |
|---|---|---|
| L0 | 能导入 JSON、字段不丢 | 导入/导出 round-trip |
| L1 | 静态 HTML/JSON 搜索/详情/目录/正文 | fixture 全绿 |
| L2 | 常见 JS + `java.*` 桥 | 能力样本库端到端 |
| L3 | 登录、Cookie、验证码、WebView | 明确 UI 状态机 + 人工步骤 |
| L4 | 图片/字体/加密/分页等高级能力 | 字节级 fixture + 真机验证 |
| L5 | 反爬/Cloudflare/TLS 指纹 | 明确“需人工/不支持”，不伪造成功 |

本项目当前的位置：

- L0：达成；
- L1：13/13 样本声明齐全，主链 fixture 覆盖；
- L2：常用桥达成，开放集合仍在扩展；
- L3：Cookie/登录可用，验证码状态机部分完成；
- L4：插图/内联图/字体/分页可用，切片拼图缺样本；
- L5：不做无交互绕过，Cloudflare 场景标记为条件支持。

### 6.6 本项目的真实资产与缺口

已有工程资产：

| 资产 | 位置 | 规模/作用 |
|---|---|---|
| JSONPath 方言 | `Core/Rules/JSONRuleExtractor.swift` | 约 101 KB |
| HTML/CSS 规则 | `Core/Rules/HtmlRuleExtractor.swift` | 约 49 KB |
| JS 运行时 | `Core/JavaScript/JSCoreRuntime.swift` | 约 278 KB |
| Java 原生桥 | `LegadoNativeBridges.swift`、`LegadoHostServices.swift` | 约 122 KB |
| 能力样本库 | `SourceReadSwiftTests/Fixtures/legado-capability-bank-20260908.json` | 13 个真实源快照 |
| 回归 | `SourceReadSwiftTests` | 987 XCTest |

明确缺口：

1. `startBrowserAwait` / 验证码的完整 UI 状态机；
2. WebView 内 DOM 脚本执行；
3. `imageDecode` 多切片拼图；
4. `nextContentUrl` 多值 / `replaceRegex` 跨页顺序的真实语义；
5. 强反爬（Cloudflare、TLS 指纹）；
6. 7z/RAR；
7. 任意 Java/Android API；
8. `downloadUrls` 的完整下载队列（未立项，不做半成品）。

### 6.7 上游参考实现消失：兼容基线必须冻结在仓库内

2026-10-24 实测 `gedoor/legado`：默认分支只剩 `README.md` 与一张公告图，作者已删除项目内容。这不是网络故障，而是上游基线消失。

工程含义：

- 不能再把“对照最新 Kotlin 源码”作为兼容性计划的一部分；
- 仓库内的 13 源快照与各阶段 fixture 是唯一可执行规范；
- 新增能力必须先补 fixture，再写实现；
- 文档中所有“Legado 原生如何如何”的表述都应附带样本或代码证据；无法取证时标为 `Assumed`。

### 6.8 可执行路线

| 优先级 | 工作 | 验收 |
|---|---|---|
| P0（已完成） | 主链 search/detail/toc/content + 13 源 fixture | CI 全绿 |
| P0（已完成） | `isVolume` / `formatJs` / `preUpdateJs` / `reverseToc` | `ChapterListMetadataTests` |
| P1（已完成） | `imageStyle` / `imageDecode` / `payAction` / `title` / `isPay` | 对应 XCTest |
| P1（已完成） | 未知 `java.*` 降级诊断 | `JSCoreRuntimeTests` |
| P0 | `startBrowserAwait` / 验证码 UI 状态机 | 明确状态，不返回假成功 |
| P1 | JSONPath 方言差异逐条变成 XCTest | 每个差异至少一个用例 |
| P1 | 真实源脱敏后的 search/detail/toc/content 端到端 fixture | 可回放 |
| P2 | 7z/RAR 替代方案 | 导入时提示 ZIP/预解压 |
| P2 | 多切片图片拼图 | 先拿到真实切片样本 |
| P2 | `downloadUrls` 完整下载队列 | 队列/进度/重试/文件管理一起交付 |

---

## 七、阅读器架构：四模式、跨章窗口与缓存

> 本章描述 v1.0.30 的窗口与缓存模型，并标注 v1.0.60 的渲染层变化。阅读器是本项目最复杂的部分（`ReaderView.swift` 约 274 KB），也是用户感知最强的部分。

### 7.1 四种阅读模式

| 模式 | 枚举 | 实现 | 翻页方式 |
|---|---|---|---|
| 滑动 | `.scroll` | `WebScrollReaderView`（WKWebView，v1.0.48+；`NativeReaderTextView` 为旧实现） | 垂直连续滚动 |
| 平移 | `.pageTurn` | SwiftUI `TabView` | 水平整页平移 |
| 覆盖 | `.cover` | `ReaderCoverSwipePolicy` + 拖拽 | 新页从边缘覆盖旧页 |
| 仿真 | `.pageCurl` | `PageCurlReaderView`（`UIPageViewController`） | 书页卷曲动画 |

四种模式共用同一套“当前章 + 前后 N 章”窗口和同一份章节缓存；差异只在渲染表面与手势。

### 7.2 窗口模型

```text
ReaderChapterWindowPolicy
├── minimumRadius = 1          // 即使预加载设为 0，也保留前后各 1 章用于续读
├── radius(forPreloadCount:)   // 设置 0...5 映射到窗口半径
├── indices(around:radius:lowerBound:upperBound:)
├── prefetchOrder(...)         // 近邻优先；同距离向后优先
├── retainedIndices(...)       // 窗口裁剪时保留当前章、加载中章、邻章
├── upperBound(totalChapters:chapterIndices:fallback:)
└── restoreParagraphIndex(...) // 向后翻页落到上一章章尾
```

关键修复：`upperBound` **实时目录优先**。书架里保存的 `totalChapters` 可能来自上次刷新，源站删章/重排后会大于真实目录；如果窗口信任这个旧值，就会不断请求不存在的章节，表现为“读到章尾就停住”。现在：

- 有实时 `chapterIndices` → 取最大索引 + 1；
- 没有实时目录但有 `totalChapters` → 用它；
- 都没有 → 用持久化 fallback。

### 7.3 扁平段落空间与真实占位页

为了让三种分页模式都能跨章：

- 整个窗口被展开成一个**扁平段落空间**；
- 每章保留自己的标题页；
- 未加载的相邻章生成**真实占位页**，不是空白或直接回弹；
- `ReaderPageBlock` 记录章节归属、章内页序号 `pageOrdinal`、占位方向；
- `ReaderChapterPosition` 带上 `pageOrdinal`，窗口插入/删除章节后仍能保持精确页；
- `pagedPageIndex` 是全局连续页索引；滑到占位页会触发对应章节加载，回包后由 `restoredPageIndex` 落回该章第一页（向前翻则落章尾）。

这样用户在章界继续滑动时，看到的是“正在加载上一章/下一章”，而不是被 `count - 1` 弹回。

### 7.4 串行预取与直接请求抢占

v1.0.28 的并发预取会乱序：N+2 可能先于 N+1 返回，页面先出现 N+2，再在 N+1 位置留占位页，正好跨章的用户看到“卡住”。

v1.0.29 起改为：

- `prefetchQueue` / `prefetchTask` / `prefetchGeneration`；
- 按 `prefetchOrder` 逐章加载，一次只发一个请求；
- 用户当前需要的章节走 `loadWindowChapter` 直接加载，队列通过 `windowLoadingIndices` 自动跳过；
- `resetWindow` / `seedWindow` / `onDisappear` 取消预取，用 `windowGeneration` + `prefetchGeneration` 双令牌丢弃旧回包；
- 预加载调到前后各 5 章也不会瞬间并发 10 个请求。

### 7.5 章级分页缓存

v1.0.30 之前，邻章回包会导致整个窗口重新分页，当前页跳动。现在：

- `ReaderChapterPageCacheEntry` 按章保存分页结果；
- `chapterPageLayoutSignature`：排版参数（字号、行距、边距、字体、容器尺寸等）；
- `chapterPageContentSignature`：章节内容版本；
- 组装窗口时只重编全局页 id，不重排未变化的章；
- 内容刷新或模式切换时用 `rebuildPagedBlocksCache(useCachedPageAnchor:)` 从实时阅读位置重建，避免复用失效的 `pageOrdinal`。

### 7.6 失败重试

```swift
enum ReaderChapterRetryPolicy {
    static let maximumAutomaticAttempts = 3
    static func delay(afterAttempt attempt: Int) -> TimeInterval? {
        // attempt 0 → 2s, 1 → 5s, 2 → 10s, 其余 nil
    }
}
```

- 同一章最多自动重试 3 次，退避 2 / 5 / 10 秒；
- 之后停止自动重试，占位页保留手动“重试”按钮；
- `windowRetryTasks` / `windowRetryAttempts` / `windowFailures` 按章隔离；
- 失败结果 `ReaderWindowChapterOutcome` 携带错误文本，不再把失败误判为“全书结束”；
- 滚动模式在章尾/章首显示 `scrollChapterStatusBanner`（距章尾 6 段 / 章首 3 段）。

### 7.7 读即缓存（LRU）

`ChapterContentCacheStore.markRead(sourceURL:chapter:purifyRules:at:)`：

- 章节真正进入阅读位置时，把缓存条目移到队首；
- 刷新 `cachedAt`；
- 上限仍为 500 章；
- 读过的章不会因为后台预取 500 个新章而被淘汰；退出重进或向前回翻直接命中磁盘。

### 7.8 自动预取所有权收敛

v1.0.30 删除了 `BookDetailView` 的：

- `preloadTask`；
- `onDisappear` 取消块；
- 两处自动 `preloadAdjacentChapters(...)` 调用。

原因：详情页自动预取和阅读器窗口预取同时存在时会重复请求同一章、互相淘汰缓存。现在自动预取只由阅读窗口负责。

手动“缓存前后章节”保留：

```text
阅读器 onCacheNextChapters
  → cacheAdjacentChaptersFromReader
  → chaptersToCache（跳过已缓存）
  → isCachingNext 防重入
```

### 7.9 页脚与边界提示

- 分页模式页脚：`第 X / Y 章 · Z% · 页 a/b`；
- `b` 是**当前章总页数**（`chapterPageCounts`），不是会随预取增长的窗口总页数；
- 滚动模式：距章尾 6 段 / 章首 3 段显示加载/失败胶囊，并提供手动重试。

### 7.10 自动化与 TTS 跨章

- 音频朗读和自动滚动跨章时不再销毁阅读器；
- 窗口命中 → 原位续播/续滚；
- 缺章 → 先进入 pending，章节到达后恢复；
- `ReaderAutomationPolicy` 负责自动滚动节奏、暂停条件与边界。

### 7.11 真机验收清单（尚未完成）

本机没有 Xcode/真机，以下必须由设备验证，不能写成“已通过”：

- [ ] 滑动模式：长章节连续滚动到章尾，是否无缝进入下一章；
- [ ] 平移模式：章界占位页左右滑动的手感与回弹；
- [ ] 覆盖模式：占位页被真实页替换时的视觉连续性；
- [ ] 仿真模式：`UIPageViewController` 在占位页替换时的页码与动画；
- [ ] 向前翻：从章首左滑是否落到上一章章尾；
- [ ] 弱网：2/5/10 秒重试的用户感知，失败后手动重试入口；
- [ ] 预取回包与用户滑动同时发生时的落点；
- [ ] 超长章节窗口裁剪后的回翻；
- [ ] 深色主题、横屏安全区、页脚与悬浮胶囊是否重叠；
- [ ] 漫画放大后的平移（当前只有缩放，且与 TabView 手势冲突）。

---

## 八、版本演进：v1.0.22 → v1.0.30

> 本章只记录有代码或 CI 证据的版本。更早的 v1.0.x 历史见 `PROJECT_HANDOVER.md` 与 `progress.md`（后者是 173 KB 的过程记录，只作历史参考）。

### 8.1 版本总表

| 版本 | 主题 | 关键代码提交 | 自动化证据 |
|---|---|---|---|
| v1.0.22 | 书籍插图与漫画排版闭环 | 见 HANDOVER 第 2 节 | 历史 CI |
| v1.0.23 | `ruleContent.payAction` 付费动作链路 | 见 HANDOVER 第 7 节 | `PayActionTests` 18 例 |
| v1.0.24 | `ruleContent.title`、`BookChapter.isPay`、版本单一来源 | `cbc7809`、`435497a` | 见 HANDOVER 第 8 节 |
| v1.0.25 | 未知 `java.*` 调用降级为可诊断空值 | `99c707c`、`0b46689` | `JSCoreRuntimeTests` |
| v1.0.26 | `ruleContent.imageDecode` 字节负载内联图像管线 | `99db867` | CI 932 tests（见 HANDOVER） |
| v1.0.27 | 分页表面与阅读界面整改 | `f9469ac`、`51b57fe`、`866523a`、`bb46349` | 见 HANDOVER 第 11 节 |
| v1.0.28 | 双向跨章窗口、无限前后翻、预缓存 | `04456b2`、`52a97f4`、`74b0ceb`、`6dd70d7`、`285950e` | run `40107402912`，983 tests |
| v1.0.29 | 串行近邻预取、向后翻页落章尾 | `7773e2b` | run `40109182540`，984 tests |
| v1.0.30 | 章级分页缓存、读即缓存 LRU、失败重试 | `91c9161` | run `40112864505`，987 tests |

### 8.2 v1.0.22：插图与漫画排版

- `ReaderImageStyle`：DEFAULT / FULL / TEXT / SINGLE 四种样式；
- `ReaderImageSizingPolicy`：按容器宽度、样式、最大高度计算尺寸；URL 必须有合法 scheme；
- `RemoteImageLoader`：全局共享内存图片缓存 + 请求去重 + 异步解码；
- `NativeReaderTextView`：识别 `[img]url[/img]`，生成 `NSTextAttachment`，异步加载后局部重排并保持阅读位置；
- `ReaderView` 翻页模式：`ReaderIllustrationView` 适配 FULL/SINGLE 撑满列宽，DEFAULT 限制 260pt；
- 防盗链：`SourceRequestBuilder.imageRequestHeaders` 透传 Referer / UA。

### 8.3 v1.0.23：`payAction`

- `PayActionPolicy`：纯 URL 不进入 JS；`{{...}}` 模板逐段求值；`@js:` / `<js>` 交给 runtime；
- 分类对齐 Legado `isAbsUrl()` / `isTrue()`：`false/no/not/0/空/null` 为假，其余非空为真；
- `performPayAction`：同一 JS 上下文、Cookie、持久变量、同步网络桥；
- 购后缓存失效与刷新；
- `PayActionTests` 18 个用例：求值、分类、缓存、Codable。

### 8.4 v1.0.24：标题、`isPay`、版本单一来源

- `ruleContent.title`：在正文 HTML/JSON 响应上执行，HTML 在 document root 求值，空值/失败回退目录标题；
- `BookChapter.isPay: Bool?`：旧缓存为 nil；HTML/JSON 独立解析 `isPay/paid/purchased`；
- 目录按钮条件改为 `hasLogin && isVip && isPay != true`；
- `project.yml` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 成为唯一版本源，CI 断言 plist 不漂移。

### 8.5 v1.0.25：未知 `java.*` 降级

- 之前：书源调用未实现的 `java.*` → TypeError → 整条规则失败；
- 现在：prelude 末尾安装 Proxy，未知调用降级到原生 dispatcher，记录 `bridge.error java.<name>`，返回空串；
- 不伪造成功，但让失败可诊断、可继续执行其他字段；
- `JSCoreRuntimeTests` 覆盖降级与诊断。

### 8.6 v1.0.26：`imageDecode` 内联图

- 支持四类负载：data URI、裸 base64、`byte[]` JSON 数组、数字键对象；
- 魔数校验、32 MB 上限；
- `InlineImageStore`：`srdata://` 注册表、SHA256 去重、256 MB 裁剪、排除 iCloud 备份；
- 阅读器两端渲染：TextKit `NSTextAttachment` + 翻页 `ReaderIllustrationView`；
- `InlineImagePipelineTests` 7 个用例：解码形态、入库、真实 UIImage 解码、坏负载回退、去重与路径穿越。

### 8.7 v1.0.27：分页表面与阅读界面

- 统一分页表面的页码、点击区域和标题页；
- 标题页可寻址，分块测量精确；
- 阅读设置面板限制在可视区域内；
- 滚动模式点击区域复活，增加保留页脚，停止过期章节内容；
- 这一版解决了“阅读界面很多功能缺失/没有对齐”的第一批结构问题，但视觉细调仍需真机。

### 8.8 v1.0.28：双向跨章窗口

- 四模式共用“当前章 + 前后 N 章”窗口；
- 滚动模式用扁平段落空间续接；覆盖/平移/仿真用真实占位页跨边界；
- 章与章之间不再重置页码；
- 未加载邻章生成占位页，TabView / 拖拽 / `UIPageViewController` 都能滑过章界；
- 窗口插入/删除章节时用 `ReaderChapterPosition` + `pageOrdinal` 保持精确页；
- 修复空书/越界章号导致窗口裁剪崩溃、滚动兜底把扁平索引误当章内索引、内容刷新旧页码落错章、前置插入导致 TextKit 锚点漂移、音频/自动滚动跨章销毁阅读器。

验证：

- iOS run `40107402912` / job `120911836046`，commit `285950e`，983 tests / 0 failures；
- IPA run `40107402785`，11,462,716 字节，SHA256 `AA382E773C727F9FD95EDA3FF51AFA6554B85E939780DF6779CE4EDB8BA96402`；
- 四件套 `E:\codex-temp\sourceread\artifacts\reader-continuous-v28\`，12 个文件回滚后逐字节一致。

### 8.9 v1.0.29：串行预取与向后落章尾

- `prefetchQueue` / `prefetchTask` / `prefetchGeneration`；
- 近邻优先、同距离向后优先，一次只发一个请求；
- 用户当前章走直接加载，队列跳过 `windowLoadingIndices`；
- 双 generation 令牌丢弃切书/切章后的旧回包；
- `restoreParagraphIndex`：向前翻页落到上一章章尾，而不是章首；
- 预加载调到前后各 5 章也不会并发 10 个请求。

验证：

- iOS run `40109182540` / job `120917402615`，commit `7773e2b`，984 tests / 0 failures；
- IPA run `40109182535`，11,466,987 字节，SHA256 `C2CC7A38778A76338E6BDA61BC14D0E75BF908A88C7F72485D06368CF6AD8D2A`。

### 8.10 v1.0.30：章级分页缓存、读即缓存、失败重试

- `ReaderChapterWindowPolicy.upperBound(totalChapters:chapterIndices:fallback:)`：实时目录优先；
- `ReaderChapterPageCacheEntry` + `chapterPageLayoutSignature` / `chapterPageContentSignature`：章级分页缓存；
- `ReaderChapterRetryPolicy`：2 / 5 / 10 秒，3 次自动重试；
- `ReaderWindowChapterOutcome`：失败携带错误文本；
- `ChapterContentCacheStore.markRead`：读即移到队首 + 刷新 `cachedAt`，500 章上限；
- `BookDetailView` 删除自动预取，所有权收敛到阅读窗口；
- 页脚改为章内页码；滚动模式增加边界胶囊。

验证：

- iOS run `40112864505` / job `120928037334`，commit `91c9161`，987 tests / 0 failures；
- IPA run `40112864571` / job `120928037986`，11,507,953 字节，SHA256 `05F3EC27C1FD065D91289045229D0B25A2DCF4E5E5A1FCFCE86313624AA10261`。

### 8.11 版本递进关系

```text
v1.0.27  修阅读界面的“可用性”（页码/点击/设置面板/页脚）
   │
v1.0.28  修“能不能连续读”（双向窗口 + 占位页 + 跨章位置）
   │
v1.0.29  修“连续读是否稳定”（串行预取 + 向后落章尾 + 旧回包丢弃）
   │
v1.0.30  修“连续读是否不卡、不丢、不误判”（章级分页缓存 + 读即缓存 + 失败重试 + 实时目录上限）
```

---

## 九、本轮 v1.0.30 工作全记录

> 本章记录本轮实际做了什么、改了哪些文件、用什么证据证明。所有数字来自 `git show`、GitHub Actions 日志与本地产物，未运行的项目明确标注。

### 9.1 起点与目标

起点：v1.0.29（`7773e2b`，984 tests）。

用户目标：阅读模式要像成熟阅读 App 一样，**可以无限前后滑动，而不是滑完一章再手动点下一章**；要提前缓存前后章；读过的章应保留，而不是看完就没了。

本轮把这个目标拆成四个可验证问题：

1. 窗口上限是否会被过期的 `totalChapters` 卡住，导致章界请求不存在的章节；
2. 邻章回包是否会导致整窗重排、当前页跳动；
3. 弱网/单章失败是否会被误判为“全书结束”；
4. 预取与详情页预加载是否重复请求、互相淘汰缓存。

### 9.2 变更范围

`git show --stat 91c9161`：

```text
SourceReadSwift/App/Info.plist                              |   4 +-
SourceReadSwift/Core/Storage/ChapterContentCacheStore.swift |  38 ++
SourceReadSwift/Features/Discover/BookDetailView.swift      |  41 --
SourceReadSwift/Features/Reader/ReaderChapterWindow.swift   |  55 ++-
SourceReadSwift/Features/Reader/ReaderView.swift            | 540 ++++++++++++++++++---
SourceReadSwift/Shared/AppVersion.swift                     |   4 +-
SourceReadSwiftTests/ChapterContentCacheStoreTests.swift    |  20 +
SourceReadSwiftTests/ReaderChapterWindowPolicyTests.swift   |  44 ++
SourceReadSwiftTests/SearchURLResolverTests.swift           |   6 +-
project.yml                                                 |   4 +-
10 files changed, 628 insertions(+), 128 deletions(-)
```

### 9.3 七项实现

#### A. 实时目录优先的窗口上限

`ReaderChapterWindowPolicy.upperBound`：

```swift
static func upperBound(
    totalChapters: Int?,
    chapterIndices: [Int],
    fallback: Int
) -> Int
```

规则：

- 有实时 `chapterIndices` → `max(highest + 1, fallback)`；
- 没有实时目录 → 用 `totalChapters`；
- 都没有 → 用持久化 fallback。

解决的问题：书架保存的章数可能大于真实目录；旧逻辑不断请求不存在章节，章界表现成“停住”。

#### B. 章级分页缓存

新增：

- `ReaderChapterPageCacheEntry`；
- `chapterPageLayoutSignature`：排版参数指纹；
- `chapterPageContentSignature`：内容指纹。

行为：

- 每章独立缓存分页结果；
- 邻章回包只组装、不重排未变化章；
- 组装时重编全局页 id；
- 内容刷新/模式切换用 `rebuildPagedBlocksCache(useCachedPageAnchor:)` 从实时位置重建。

解决的问题：预取回包导致当前页跳动；切换模式后页码错位。

#### C. 失败自动重试

`ReaderChapterRetryPolicy`：

```swift
maximumAutomaticAttempts = 3
delay(afterAttempt:) // 0→2s, 1→5s, 2→10s, 其余 nil
```

配套：

- `windowRetryTasks` / `windowRetryAttempts` / `windowFailures` 按章隔离；
- 失败后占位页显示错误文本 + 手动重试；
- 滚动模式显示 `scrollChapterStatusBanner`；
- 不会把单章失败当成全书结束。

#### D. 读即缓存（LRU）

`ChapterContentCacheStore.markRead(sourceURL:chapter:purifyRules:at:)`：

- 命中后移到队首；
- 刷新 `cachedAt`；
- 重启后仍保留；
- 上限 500 章；
- 读过的章不会因后台预取被优先淘汰。

#### E. 预取所有权收敛

`BookDetailView` 删除：

- `preloadTask`；
- `onDisappear` 取消块；
- 两处自动 `preloadAdjacentChapters(...)`。

保留：

- 手动“缓存前后章节”；
- `onCacheNextChapters` → `cacheAdjacentChaptersFromReader`；
- `chaptersToCache` 跳过已缓存；
- `isCachingNext` 防重入。

解决的问题：详情页与阅读窗口重复请求同一章、互相淘汰缓存。

#### F. 页脚与滚动边界提示

- 分页页脚：`第 X / Y 章 · Z% · 页 a/b`；
- `b` = 当前章总页数；
- 滚动模式：距章尾 6 段 / 章首 3 段显示加载/失败胶囊；
- 手动重试入口。

#### G. 测试与版本

- `ChapterContentCacheStoreTests.testMarkReadMovesEntryToFrontAndPersists`；
- `ReaderChapterWindowPolicyTests.testUpperBoundPrefersTheLiveTOC`；
- `ReaderChapterRetryPolicy` 三次上限用例；
- `SearchURLResolverTests` 版本断言更新到 1.0.30 / Build 31；
- `project.yml`、`Info.plist`、`AppVersion` 同步。

### 9.4 本轮同时修复/覆盖的边界缺陷

这些缺陷在 v1.0.28–v1.0.30 的连续改造中被发现并修复，均有代码或测试证据：

1. `retainedIndices` 在空书/越界章号返回不存在的索引 → 按 `lowerBound/upperBound` 过滤；
2. 滚动兜底把扁平段落索引当成章内索引 → 统一转换为 `ReaderChapterPosition`；
3. 内容刷新后旧页码落到新章节错误页 → 从实时阅读位置重建；
4. 前置章节插入导致 TextKit 字符锚点漂移 → 用窗口差异位移恢复；
5. 音频朗读/自动滚动跨章销毁阅读器 → 窗口命中续播，缺章 pending 后恢复；
6. 预取乱序导致章界空洞 → 串行近邻优先；
7. 向后翻页落章首而非章尾 → `restoreParagraphIndex`；
8. 旧请求污染新窗口 → 双 generation 令牌；
9. 单章失败被当成全书结束 → 失败 outcome + 重试 + 手动入口；
10. 详情页与阅读器重复预取 → 所有权收敛。

### 9.5 测试证据

| 项 | 值 |
|---|---|
| 代码提交 | `91c9161` |
| iOS run / job | `40112864505` / `120928037334` |
| 结果 | `** TEST SUCCEEDED **` |
| 用例 | **987 tests / 0 failures / 0 unexpected** |
| 基线 | v1.0.29：984 tests / 0 failures |
| 净增 | 3 个用例 |
| 关键新增 | `markRead` 持久化与队首、`upperBound` 实时目录、重试三次上限 |

### 9.6 四件套与回滚演练

路径：`E:\codex-temp\sourceread\artifacts\reader-continuous-v30\`

| 产物 | 内容 |
|---|---|
| `BASELINE/` | 改动前 10 个文件 |
| `MODIFIED/` | 改动后 10 个文件 |
| `DIFF.patch` | 从 BASELINE 重建 MODIFIED 的补丁 |
| `VERIFICATION.txt` | 命令、输出、哈希、变更点、状态 |
| `ROLLBACK.sh` | 可执行回滚 |
| `DRILL/BASELINE`、`DRILL/MODIFIED`、`DRILL/WORK` | 独立副本回滚演练 |
| `FILES.txt` / `STAT.txt` | 文件清单与统计 |

演练结果：**10/10 文件 SHA256 与基线一致**。

### 9.7 CI 与 IPA 证据（两套）

#### 代码提交 `91c9161`

| 工作流 | Run | Job | 结果 |
|---|---|---|---|
| iOS | `40112864505` | `120928037334` | build + test success，987 tests |
| Unsigned IPA | `40112864571` | `120928037986` | success |

#### 上一版文档 HEAD `5173230`

| 工作流 | Run | Job | 结果 |
|---|---|---|---|
| iOS | `40114220909` | `120932360168` | build + test success，987 tests |
| Unsigned IPA | `40114220955` | `120932337268` | success |

#### 本文件提交 `75aeb44`

| 工作流 | Run | Job | 结果 |
|---|---|---|---|
| iOS | `40121317778` | `120953254683` | build + test success，987 tests / 0 failures |
| Unsigned IPA | `40121317766` | `120953254569` | success |

说明：

- `594ed57` 触发的 `40114078830` / `40114078838` 因推送 `5173230` 被并发组取消，属正常；
- 文档 HEAD 的 IPA workflow 只核对成功，不声称已下载并校验该次产物；本地 IPA 来自 `91c9161` 的 `40112864571`。

### 9.8 IPA 产物核对

| 项 | 值 |
|---|---|
| 路径 | `C:\Users\Edc21\Desktop\SourceReadSwift-1.0.30-unsigned.ipa` |
| 大小 | `11,507,953` 字节 |
| SHA256 | `05F3EC27C1FD065D91289045229D0B25A2DCF4E5E5A1FCFCE86313624AA10261` |
| `CFBundleShortVersionString` | `1.0.30` |
| `CFBundleVersion` | `31` |
| `MinimumOSVersion` | `16.0` |
| `CFBundleIdentifier` | `com.edc21.SourceReadSwift` |
| 校验方式 | workflow 内 `PlistBuddy` 断言 + 本地 `plistlib` 复验 |

### 9.9 文档交付

| 文档 | 状态 |
|---|---|
| `PROJECT_HANDOVER.md` | 已更新到 v1.0.30 / Build 31，含第 14 节增量与 CI 证据 |
| `PROJECT_FULL.md` | 本文件，项目全量说明 + 本轮工作记录（提交 `75aeb44`） |
| `docs/IOS-JSON-ECOSYSTEM-DEEP-DIVE.md` | 生态与 12 断层分析 |
| `docs/SOURCE-CAPABILITY-MATRIX.md` | 13 源能力矩阵 |
| `docs/JSON-IOS-COMPATIBILITY.md` | iOS 兼容性报告 |

### 9.10 本轮未完成 / 交接事项

1. **真机验收**：四模式跨章手势、动画连续性、弱网重试感知（本机无 Xcode/真机）；
2. **UI 视觉收口**：用户已反馈主页书架“太奇怪”、阅读界面功能/对齐问题；本轮明确暂停，未改；
3. **漫画平移**：只有 1×–3.5× 缩放，无 pan；
4. **`startBrowserAwait` / 验证码状态机**：部分完成；
5. **多切片 `imageDecode`**：缺真实样本；
6. **`nextContentUrl` 多值 / `replaceRegex` 跨页顺序**：需 fixture 固定语义；
7. **`downloadUrls`**：未消费，不渲染入口；
8. **强反爬/Cloudflare/TLS 指纹**：条件支持，不做无交互绕过。

---

## 十、构建、发布与复现

### 10.1 本机限制

当前工作机是 Windows：

- 没有 Xcode、`swiftc`、`xcrun`、iOS 模拟器；
- 不能本地编译、不能本地跑 XCTest、不能本地签名；
- 所有编译/测试/IPA 必须走 GitHub Actions 的 `macos-15`；
- Windows 可以编辑、提交、推送、读日志、校验 IPA 包结构。

因此本文档中所有“构建通过/测试通过”的证据都来自 CI，不来自本地。

### 10.2 仓库与分支

```text
工作区：D:\Gemini反重力\SourceReadSwift2
分支：  codex/swift-v2-lifetime-reader
远端：  https://github.com/ztcsr5/SourceReadSwift
```

注意：

- 本机 `git remote` 已嵌入认证 token，**不要在日志、文档、聊天中打印 remote URL**；
- 直连 `git fetch/push` 可能失败；项目内使用 `E:\codex-temp\sourceread\scripts\push_commit.py <sha>` 推送；
- 推送后本地远端 ref 需要手动更新：

```powershell
git update-ref refs/remotes/origin/codex/swift-v2-lifetime-reader <sha>
```

### 10.3 CI 工作流

#### iOS（`.github/workflows/ios.yml`）

- 触发：`workflow_dispatch`、push 到 `main` / `feat/**` / `codex/**` / `native/**` / `develop`、PR 到 `main` / `develop`；
- Runner：`macos-15`；
- 步骤：checkout → `brew install xcodegen` → `xcodegen generate` → `xcodebuild build`（iOS Simulator）→ `xcodebuild test`；
- 失败时输出 `error:` / `fatal error:` 摘要与日志尾部；
- 并发组：同一 workflow + ref，`cancel-in-progress: true`。

#### Unsigned IPA（`.github/workflows/unsigned-ipa.yml`）

- 触发：`workflow_dispatch`、push 到 `codex/**`；
- 步骤：checkout → xcodegen → `xcodebuild -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO` → 找 `.app` → 组 `Payload/` → zip 成 `.ipa` → 上传 artifact；
- 同一并发组，旧 run 会被新推送取消。

### 10.4 复现步骤

#### 方式一：推送触发（推荐）

```powershell
cd 'D:\Gemini反重力\SourceReadSwift2'
git status --short
git add <files>
git commit -m "<message>"
python -X utf8 E:\codex-temp\sourceread\scripts\push_commit.py 5173230d55fa21f3108a75b0ecac4bb1439a52a3
```

推送后：

```powershell
python -X utf8 E:\codex-temp\sourceread\scripts\ci_recent.py
python -X utf8 E:\codex-temp\sourceread\scripts\ci_jobs.py <run_id>
python -X utf8 E:\codex-temp\sourceread\scripts\fetch_job_log.py <job_id>
```

#### 方式二：手动触发

GitHub → Actions → 选择 `iOS` 或 `Unsigned IPA` → Run workflow → 选择分支 `codex/swift-v2-lifetime-reader`。

#### 方式三：macOS 本地

```bash
brew install xcodegen
cd SourceReadSwift2
xcodegen generate
xcodebuild   -project SourceReadSwift.xcodeproj   -scheme SourceReadSwift   -destination 'generic/platform=iOS Simulator'   CODE_SIGNING_ALLOWED=NO   build
xcodebuild   -project SourceReadSwift.xcodeproj   -scheme SourceReadSwift   -destination 'platform=iOS Simulator,name=iPhone 16'   CODE_SIGNING_ALLOWED=NO   test
```

### 10.5 IPA 校验

```python
import hashlib, plistlib, zipfile, os

ipa = r"C:\Users\Edc21\Desktop\SourceReadSwift-1.0.30-unsigned.ipa"
print("size", os.path.getsize(ipa))
print("sha256", hashlib.sha256(open(ipa, "rb").read()).hexdigest().upper())

with zipfile.ZipFile(ipa) as z:
    plist_path = "Payload/SourceReadSwift.app/Info.plist"
    pl = plistlib.loads(z.read(plist_path))
    for k in ("CFBundleIdentifier", "CFBundleShortVersionString",
              "CFBundleVersion", "MinimumOSVersion", "CFBundleDisplayName"):
        print(k, pl.get(k))
```

期望：

```text
size 11507953
sha256 05F3EC27C1FD065D91289045229D0B25A2DCF4E5E5A1FCFCE86313624AA10261
CFBundleIdentifier com.edc21.SourceReadSwift
CFBundleShortVersionString 1.0.30
CFBundleVersion 31
MinimumOSVersion 16.0
CFBundleDisplayName 纸间
```

### 10.6 真机安装

IPA 未签名，需要下列方式之一：

| 方式 | 说明 |
|---|---|
| AltStore | 用 Apple ID 重签，免费账号 7 天有效 |
| Sideloadly | Windows 可直接重签安装 |
| TrollStore | 仅支持特定 iOS 版本，永久签名 |
| Xcode 真机 | 有 macOS 时用免费开发者账号签名 |
| 企业签名 | 需自有证书，注意合规 |

安装后首次启动需要信任描述文件（设置 → 通用 → VPN 与设备管理）。

### 10.7 真机验收清单

- [ ] 冷启动进入书架，不闪退；
- [ ] 导入一个 JSON 书源，搜索关键词能出结果；
- [ ] 打开详情，目录能加载；
- [ ] 打开正文，四种模式都能翻页；
- [ ] 滑动到章尾能自动进入下一章；
- [ ] 从章首向前滑能回到上一章章尾；
- [ ] 弱网/断网时能看到“正在加载/失败/重试”，不是空白或假结束；
- [ ] 读过的章回翻不重新请求；
- [ ] 阅读设置修改后立即生效，重启保留；
- [ ] 书签、朗读、自动滚屏、定时关闭可用；
- [ ] 漫画缩放、视频播放、有声书后台播放可用；
- [ ] RSS 导入/阅读/已读可用；
- [ ] WebDAV 备份/恢复可用；
- [ ] Web 写源在局域网可访问。

### 10.8 常见故障排查

| 现象 | 排查 |
|---|---|
| CI 在 `xcodegen generate` 失败 | `project.yml` 缩进、源文件路径、依赖版本 |
| 编译报 Swift 并发 | `Sendable`、actor 隔离、主线程 UI |
| 测试超时 | 模拟器键盘/弹层、`XCTestConfigurationFilePath` 分支 |
| IPA 版本不对 | `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 是否同步，CI plist 断言 |
| IPA 安装失败 | 签名方式、设备 iOS 版本 ≥ 16.0、描述文件信任 |
| 推送失败 | 用 `push_commit.py`，不要直接 `git push` |
| 旧 run 被取消 | 并发组 `cancel-in-progress`，属正常 |

---

## 十一、已知边界、缺陷与后续路线

### 11.1 阅读器

| 项 | 状态 | 说明 |
|---|---|---|
| 四模式跨章手势 | 待真机验收 | 代码/单测完成，真机未点 |
| 章界动画连续性 | 待真机验收 | 占位页替换真实页时可能闪 |
| 弱网重试感知 | 待真机验收 | 2/5/10 秒是否符合预期 |
| 漫画放大平移 | 未实现 | 缩放与 TabView 手势冲突 |
| 超长章节窗口裁剪 | 待真机验收 | 回翻体验 |
| 深色/横屏/页脚重叠 | 待真机截图 | 视觉问题 |
| 阅读界面功能对齐 | 待办 | 用户已反馈，本轮未改 |
| 统一分页内核 | 建议 | 四模式仍有各自路径，可收敛为共享页模型 |

### 11.2 书源

| 项 | 状态 | 说明 |
|---|---|---|
| `startBrowserAwait` | 部分 | 缺完整 UI 状态机 |
| 验证码 | 部分 | 有 Coordinator + 弹层，复杂流程未覆盖 |
| WebView DOM 脚本 | 不支持 | 规则在 JSCore 求值 |
| `androidId` | 固定值 | 不伪造真机 |
| Promise | 同步 facade | 非真正异步 |
| `imageDecode` 切片拼图 | 未实现 | 缺真实样本 |
| `downloadUrls` | 未消费 | 不做死按钮 |
| `nextContentUrl` 多值 | 待语义固定 | 需 fixture |
| `replaceRegex` 跨页顺序 | 待语义固定 | 需 fixture |
| `sourceRegex` | 待验证 | 需具体源 |
| 7z/RAR | 不支持 | 导入提示 ZIP/预解压 |
| Cloudflare/TLS 指纹 | 条件支持 | 不承诺无交互绕过 |
| SM4/GOST | 未覆盖 | 需新桥 + fixture |
| 任意 Java/Android API | 不完整 | 常用 facade + 诊断 |

### 11.3 UI

用户已经提出但本轮明确暂停的项：

1. **主页书架“太奇怪”**：布局、密度、分组/筛选的视觉层级；
2. **阅读界面功能缺失/未对齐**：菜单分组、设置项排布、页脚/胶囊/状态栏关系；
3. **阅读模式滑动 BUG**：三种分页模式的手感与边界。

这些都是真实待办，但**不在本轮范围内**。本轮只修连续性/缓存/重试的底层链路，没有改视觉。

### 11.4 工程与性能

| 项 | 观察 | 建议 |
|---|---|---|
| `ReaderView.swift` 222 KB | 单文件过大，改动风险高 | 拆分为窗口/预取/分页/菜单/手势子模块 |
| `JSCoreRuntime.swift` 278 KB | 兼容层持续增长 | 按 `java.*` 域拆文件 + 能力注册表 |
| `SourceManagerView.swift` 114 KB | 管理/诊断/导入/编辑混在一起 | 拆成列表、详情、诊断、导入四个视图 |
| 500 章缓存 | 磁盘占用 | 已有上限与裁剪；可加按书清理 |
| 987 测试 | 单次 CI 时间 | 可拆 test plan / 并行 |
| 真机性能 | 未测 | 120Hz、长列表、TextKit 大段排版 |

### 11.5 优先级路线

#### P0（下一轮必须）

1. 真机验收四模式跨章，记录每项结果；
2. 修复真机暴露的手势/动画/落点问题；
3. `startBrowserAwait` / 验证码 UI 状态机；
4. 用户反馈的书架/阅读界面视觉收口（另开 UI 任务，不与阅读内核混在一起）。

#### P1

1. `imageDecode` 多切片拼图（先拿样本）；
2. `nextContentUrl` 多值 / `replaceRegex` 跨页顺序 fixture；
3. JSONPath 差异逐条 XCTest；
4. 书源健康度自动降级；
5. 漫画平移与手势阈值；
6. 阅读器拆分与性能采样。

#### P2

1. `downloadUrls` 完整下载队列；
2. 7z/RAR 替代方案；
3. SM4/GOST；
4. 统一分页内核；
5. 更多第三方书源适配器。

### 11.6 不建议做的事

- 只加 UI 入口、不加队列/进度/重试的“下载”功能；
- 用假成功掩盖 `startBrowserAwait` / 验证码 / 付费；
- 在没有真实样本时猜测图片切片坐标或字体映射；
- 把“CI 编译通过”写成“真机体验通过”；
- 在阅读器内核未稳定时同时大改视觉，导致问题无法归因。

---

## 十二、文档索引与证据索引

### 12.1 仓库文档

| 文档 | 用途 |
|---|---|
| `PROJECT_FULL.md` | 本文件：全量说明 + 工作记录 |
| `PROJECT_HANDOVER.md` | 交接备忘录：v1.0.22 → v1.0.30 细节 |
| `README.md` | 项目目标与构建入口 |
| `progress.md` | 历史进度（173 KB，过程记录） |
| `docs/IOS-JSON-ECOSYSTEM-DEEP-DIVE.md` | iOS 生态与 12 断层 |
| `docs/JSON-IOS-COMPATIBILITY.md` | JSON 书源兼容性报告 |
| `docs/SOURCE-CAPABILITY-MATRIX.md` | 13 源能力矩阵 |
| `docs/legado-js-compatibility-matrix.md` | JS/Java facade 矩阵 |
| `docs/legado-source-capability-table-20260908.md` | 单源能力明细 |
| `docs/source-rule-guide.md` | 书源规则指南 |
| `docs/BUILD.md` | 构建说明 |
| `docs/APP_STORE_READINESS.md` | 上架准备 |
| `docs/stage-*.md` | 各阶段验收 |
| `docs/superpowers/specs/` | 10 份设计规格 |
| `docs/superpowers/plans/` | 下一阶段计划 |
| `docs/ui-reference/20260907/` | 8 张 UI 参考图 |

### 12.2 外部产物与脚本

| 路径 | 用途 |
|---|---|
| `C:\Users\Edc21\Desktop\SourceReadSwift-1.0.30-unsigned.ipa` | 最新未签名 IPA |
| `E:\codex-temp\sourceread\artifacts\reader-continuous-v30\` | v1.0.30 四件套 + 回滚演练 |
| `E:\codex-temp\sourceread\artifacts\reader-continuous-v28\` | v1.0.28 四件套 |
| `E:\codex-temp\sourceread\scripts\push_commit.py` | 推送提交 |
| `E:\codex-temp\sourceread\scripts\ci_recent.py` | 最近 CI run |
| `E:\codex-temp\sourceread\scripts\ci_jobs.py` | 指定 run 的 job |
| `E:\codex-temp\sourceread\scripts\fetch_job_log.py` | 下载 job 日志 |
| `E:\codex-temp\sourceread\scripts\fetch_ipa_v28.py` | 下载 IPA |
| `E:\codex-temp\sourceread\scripts\parse_swift.py` | Swift 静态检查 |

### 12.3 关键提交与运行号

| 类型 | 标识 | 说明 |
|---|---|---|
| 代码 | `91c9161` | v1.0.30 实现 |
| 文档 | `594ed57` | v1.0.30 交接文档 |
| 文档 | `5173230` | 预取所有权说明修正 |
| 文档 | `75aeb44` | 全量文档 PROJECT_FULL.md（本文） |
| 代码 | `7773e2b` | v1.0.29 |
| 代码 | `285950e` | v1.0.28 收尾 |
| iOS run | `40112864505` | 91c9161，987 tests |
| IPA run | `40112864571` | 91c9161，IPA |
| iOS run | `40114220909` | 5173230，987 tests |
| iOS run | `40121317778` | 75aeb44，987 tests |
| IPA run | `40121317766` | 75aeb44，IPA workflow success |
| IPA run | `40114220955` | 5173230，IPA workflow success |
| iOS run | `40109182540` | 7773e2b，984 tests |
| iOS run | `40107402912` | 285950e，983 tests |

### 12.4 如何继续（给下一个协作者）

1. 先读本文件的第一、五、七、九、十一章，建立“项目是什么/书源到什么程度/阅读器怎么工作/本轮改了什么/还缺什么”的框架；
2. 再读 `PROJECT_HANDOVER.md` 对应版本的细节；
3. 改代码前先看 `docs/SOURCE-CAPABILITY-MATRIX.md` 与 `docs/legado-js-compatibility-matrix.md`，确认能力状态；
4. 任何书源能力变更，必须同时补：模型字段、解析分支、UI 展示或明确不展示、fixture/XCTest、能力矩阵；
5. 任何修改类操作走 Copy-first + 四件套；
6. 本机不能编译，所有验证走 CI；
7. 真机项必须真机验收，不能拿 CI 代替；
8. 推送用 `push_commit.py`，不要打印 remote token。

---

## 十三、v1.0.60 阅读界面重构（2026-10-27）

> 本轮只改阅读界面与阅读模式，不动书源主链。目标是把“顶部空白太多、翻页有 BUG、状态栏位置不佳”收敛到竞品截图量测的同一套几何。

### 13.1 竞品基准（390×844pt @3x 截图像素量测）

| 元素 | 开元 / 栖阅基准 | v1.0.60 实现 |
|---|---|---|
| 页眉章节名 | 12pt，墨迹 y 50–61 | `headerFontSize=12`，`safeTop+2` 起，15pt 行高 |
| 正文首行顶 | 84.3pt（safeTop 50 + 34.3） | `safeTop + 2 + 15 + 17 = safeTop + 34` |
| 左右边距 | 20.7 / 21.0 | 默认 `pagePadding=21` |
| 首行缩进 | 40.3（约 2 字） | 默认 `paragraphIndent=40` |
| 正文字号 / 行距 | 20.7pt / 42.7pt | 默认 20pt / `lineSpacing=12` |
| 段距 | 0 | 默认 `paragraphSpacing=0` |
| 正文底 | 819.0 | `footerTop - 4` |
| 页码 | 右下 `3/35`，11pt，离底 12.3 | 11pt，右下，`footerBottomInset=12` |

### 13.2 单一几何来源：`ReaderPageGeometry`

旧实现有三处各自扣安全区：`pageSurface` 的 padding、分页引擎的 `viewport - topPadding - bottomPadding`、`UIHostingController` 的 safe area。三处各扣一次，就是“顶部大片空白 + 页尾截断”。

v1.0.60 新增 `SourceReadSwift/Features/Reader/ReaderPageGeometry.swift`：

```text
bodyTop   = safeTop + 2 + 15 + 17   // 页眉模式；inline/hidden 另算
footerTop = height - max(safeBottom*0.5, 12) - 14
bodyBottom= footerTop - 4
contentHeight = max(bodyBottom - bodyTop, 120)
contentWidth  = max(width - margin*2, 80)
```

分页引擎、SwiftUI 页面、页眉、页脚、页码全部只读这一份；`ReaderPageContainerMetrics` 把 `UIHostingController` 的真实 bounds 与全局原点回传，解决“按 852pt 排、容器只有 793pt”的错位。

### 13.3 每页内置页眉页脚

- 分页模式不再用全局浮动页眉/页脚覆盖页面；每一页自己画 `pagedPageHeader` / `pagedPageFooter`。
- 页码格式 `当前页/本章总页`，只在页脚右下。
- 时间/电量跟随 `statusPosition`（仅页脚 / 仅页眉 / 页眉+页脚）。
- 滚动模式的全局页眉改为 `safeTop + 2`，并修正 `padding` 与 `frame` 的顺序（先固定 22pt 行高，再加安全区偏移），避免文字被压扁。

### 13.4 翻页/覆盖/滑动修复

| 问题 | 根因 | 修复 |
|---|---|---|
| 仿真翻页点一下连翻两页 | `UIPageViewController` 自带 tap + SwiftUI 九宫格 tap 各翻一次 | `suppressInternalTapGestures` 只关 tap，保留拖动卷页 |
| 滑动模式内容下移/裁切 | 内部 `UIScrollView.contentInsetAdjustmentBehavior` 自动加安全区 | `normalizeInternalScrollViews` 统一 `.never`、inset 归零 |
| 分页高度与实际容器不一致 | `UIHostingController` 二次安全区内缩 | `edgesForExtendedLayout=.all`、`layoutMargins=.zero`、`additionalSafeAreaInsets=.zero` + 容器 metrics 回传 |
| 章节标题占正文高度 | 页眉模式仍给大标题预留 40–50pt | `appendPages` 在 header/hidden 模式不再把标题算进正文高度 |

### 13.5 跨章续读

- `ensurePagedContinuationBuffer(pageIndex:)`：读到本章倒数第 3 页就 `loadWindowChapter(next)`；接近已加载尾部时 `prefetchWindow`。
- 挂在 `onChange(pagedPageIndex)` 与 `updatePagedVisibleParagraph`，翻页/拖动/程序跳页都会触发。
- 跨章仍沿用 v1.0.28–v1.0.30 的双向窗口、真实占位页、失败重试与 LRU 缓存。

### 13.6 新设置与默认值

新增：

- `reader.chapterHeadingStyle`：页眉小标题（默认）/ 正文大标题 / 隐藏标题；
- `reader.contentExtendsIntoChrome`：内容延伸至页眉页脚区域（默认关）；
- 「一键对齐成熟阅读器排版」按钮：字号 20 / 行距 12 / 边距 21 / 缩进 40 / 段距 0 / 页眉模式 / 页脚状态栏。

默认值变更（`ReaderTypographyDefaults`）：19→20、行距 8→12、段距 6→0、缩进 38→40、标题间距 20→8、边距 20→21。

### 13.7 版本与验证

- `project.yml` / `Info.plist` / `AppVersion.swift` 三处同步：1.0.60 / Build 61。
- 新增 `ReaderPageGeometryTests` 8 个用例（竞品基准、灵动岛、inline/hidden、延伸模式、窄屏钳制、内缩容器、全屏容器、非法 metrics 回退）。
- 更新 `ReaderSettingsModelsTests` 默认值与标题文案断言；`SearchURLResolverTests` 版本断言同步 60/61。
- CI 结果：GitHub Actions run `40486194273`（commit `66e83ea4`）：Build 成功；Test `1057` 个用例、`0` 失败、`** TEST SUCCEEDED **`（2026-10-27T10:19:55Z）。
- IPA：GitHub Actions run `40486194260` 成功；产物 `C:\Users\Edc21\Desktop\SourceReadSwift-1.0.60-unsigned.ipa`，`12,024,153` 字节，SHA256 `F4960385D9A3386DAD1151CBC8FB895BFBE5861CCCA232352C3791883B073289`；包内 `CFBundleShortVersionString=1.0.60`、`CFBundleVersion=61`、`MinimumOSVersion=16.0`、`CFBundleIdentifier=com.edc21.SourceReadSwift`。

### 13.8 待真机验收

以下项目本机无 Xcode/真机，标为“待验收”，不写成已通过：

- iPhone 14 Pro Max / 15 Pro（灵动岛）：页眉不压刘海、页码在 home indicator 上方；
- iPhone SE（无刘海）：`safeTop=20` 时正文顶 = 54；
- 四种模式：上下章边界无限续读、点按不连翻、拖动卷页、覆盖跟手；
- 横屏 / 分屏：容器 metrics 变化后重新分页；
- 滚动模式：页眉 22pt 行 + 正文 30pt 内边距不重叠；
- 深色 / 自定义壁纸：页眉页脚颜色与背景对比度。

## 十四、v1.0.61 安全区与 chrome 修复（2026-10-27）

### 14.1 现象

真机截图（390×844pt）显示：顶部工具条压在系统状态栏下面，章节标题与 18:30 / 电池重叠；正文第一章标题顶到状态栏；底部控制坞贴到屏幕物理底边；设置面板底部越过 home indicator。

### 14.2 根因

阅读器根视图 `.ignoresSafeArea()` 后，安全区由代码自行计算。原实现只取 `foregroundActive` 场景的 `keyWindow.safeAreaInsets`；在 LiveContainer / 侧载容器里 key window 可能是容器窗口，安全区上报为 0，导致：

- `readerTopSafeInset = 0` → 顶部工具条 `.padding(.top, 4)`；
- `scrollContentTopInset = 30` → 正文标题顶到状态栏；
- `readerFooterSafeInset = 0` → 底部控制坞只留 10pt；
- `settingsPanel` 读取已归零的 `proxy.safeAreaInsets`。

### 14.3 修复

新增 `SourceReadSwift/Features/Reader/ReaderSafeAreaResolver.swift`：

```text
top    = max(所有 UIWindow 的 safeAreaInsets.top, 状态栏高度, 0)
top    = top < 1 ? 按屏幕尺寸兜底 : top
bottom = max(所有 UIWindow 的 safeAreaInsets.bottom, 0)
bottom = bottom < 1 && top >= 44 ? 34 : bottom
```

兜底表：932→59、926→47、896→44、852→59、844→47、812（宽≤375）→50、其余→20；横屏不启用顶部兜底。

`ReaderView` 的 chrome 同步修正：

| 位置 | 修正 |
|---|---|
| 顶部工具条 | `top = readerTopSafeInset + 4` |
| 底部控制坞 | `bottom = max(readerFooterSafeInset, 10) + 10` |
| 设置面板 | 高度与底部间距改用 `readerFooterSafeInset` |
| 顶部提示条 / 语音错误条 / 目标 toast | 全部叠加 `readerTopSafeInset` |

`ReaderPageGeometry` 本身不变；安全区恢复后页眉/正文自动回到 `safeTop + 2` 与 `safeTop + 34`。

### 14.4 验证

- 新增 `ReaderSafeAreaResolverTests` 10 个用例（灵动岛、390×844、428×926、430×932、414×896、mini、SE、窗口优先、状态栏兜底、横屏）。
- 版本三处同步：1.0.61 / Build 62。
- CI：GitHub Actions run `40489685517`（commit `e3560bc5`）：Build 成功；Test `1067` 个用例、`0` 失败、`** TEST SUCCEEDED **`（2026-10-27T10:44:18Z）。
- IPA：GitHub Actions run `40489685657` 成功；产物 `C:\Users\Edc21\Desktop\SourceReadSwift-1.0.61-unsigned.ipa`，`12,024,962` 字节，SHA256 `29C079B42733D20FD48C7B4823A547518ACF0379899413EF3679581A65727BF0`；包内 `CFBundleShortVersionString=1.0.61`、`CFBundleVersion=62`、`MinimumOSVersion=16.0`、`CFBundleIdentifier=com.edc21.SourceReadSwift`。

### 14.5 待真机验收

- 390×844：顶部工具条在状态栏下方，正文标题不与时间/电池重叠；
- 393×852 灵动岛：工具条不压灵动岛；
- 底部控制坞与设置面板完全位于 home indicator 上方；
- 横屏不额外留顶部 47pt；
- 页眉/页脚/页码与 1.0.60 几何一致。

## 十五、v1.0.62 滑动模式页脚状态带（2026-10-27）

### 15.1 现象

滑动模式下底部状态栏（时间 / 页码 / 电量）以半透明文字叠在正文最后一行上，正文被遮挡；分页 / 仿真翻页不受影响。

### 15.2 根因

`readerFooter` 是透明 overlay，滑动模式的 `WKWebView` 铺满全屏；文档内 `bottomInset` 只增加内容尾部留白，不能裁剪视口，正文仍会滚到页脚下方。

### 15.3 修复

`ReaderPageChrome` 新增：

```swift
static let scrollFooterBandHeight: CGFloat = 40
static func scrollFooterReservedHeight(statusPosition: String) -> CGFloat {
    (statusPosition == "bottom" || statusPosition == "both") ? scrollFooterBandHeight : 0
}
```

`ReaderView.scrollReaderContent` 在 `.ignoresSafeArea(.container, edges: .bottom)` 之后加 `.padding(.bottom, scrollFooterReservedHeight)`，WebView 视口在状态带上方截止；`top` / `none` 不占位。

### 15.4 验证

- 新增 `ReaderPageGeometryTests.testScrollFooterBandOnlyReservesWhenFooterAtBottom`（bottom/both=40，top/none=0）；
- CI run `40496375952`：Build 成功，`1068 tests / 0 failures`，`** TEST SUCCEEDED **`（2026-10-27T11:35:20Z）；
- IPA run `40496375949`：`C:\Users\Edc21\Desktop\SourceReadSwift-1.0.62-unsigned.ipa`，`12,026,902` 字节，SHA256 `7A33A9243D728B4D0440960FBC8467F5A8FC3A9EA32836E9A577E6BD8CCAC173`，包内 1.0.62 / Build 63。

### 15.5 待真机验收

- 章末最后一行不被页脚遮挡；
- 页脚背景与阅读背景连续；
- `statusPosition=top` 或横屏不额外留底部空白；
- 底部点击翻页不被页脚拦截。

## 附录 A：完整文件清单

> 以下为 2026-10-25 工作区实测清单。`build/`、`ci-log/`、`AppIcons_Candidates/` 为本地产物/素材，不计入源码。

### A.1 App 层

- `SourceReadSwift/App/AppState.swift`
- `SourceReadSwift/App/Info.plist`
- `SourceReadSwift/App/PrivacyInfo.xcprivacy`
- `SourceReadSwift/App/RootTabView.swift`
- `SourceReadSwift/App/SourceReadSwiftApp.swift`

### A.2 Core 层

- `SourceReadSwift/Core/Audio/AudioBookPlaybackCoordinator.swift`
- `SourceReadSwift/Core/Audio/CloudTTSClient.swift`
- `SourceReadSwift/Core/Audio/CloudTTSCredentials.swift`
- `SourceReadSwift/Core/Audio/CloudTTSPlayer.swift`
- `SourceReadSwift/Core/Audio/CloudTTSProtocol.swift`
- `SourceReadSwift/Core/Audio/HttpTTSClient.swift`
- `SourceReadSwift/Core/Audio/KeychainSecretStore.swift`
- `SourceReadSwift/Core/Audio/ReaderTTSEngine.swift`
- `SourceReadSwift/Core/Audio/XunfeiTTSFrame.swift`
- `SourceReadSwift/Core/Compression/ZlibBridge.h`
- `SourceReadSwift/Core/Engine/CryptoHelper.swift`
- `SourceReadSwift/Core/Engine/PayActionPolicy.swift`
- `SourceReadSwift/Core/Engine/SourceEngine.swift`
- `SourceReadSwift/Core/Engine/SourcePipeline.swift`
- `SourceReadSwift/Core/Engine/ZlibraryEngine.swift`
- `SourceReadSwift/Core/Environment/BackgroundKeepAliveManager.swift`
- `SourceReadSwift/Core/Environment/SandboxEnvironment.swift`
- `SourceReadSwift/Core/Import/HaiKuoShiJieSourceAdapter.swift`
- `SourceReadSwift/Core/Import/HuaHuoBookSourceAdapter.swift`
- `SourceReadSwift/Core/Import/LocalEPUBBookParser.swift`
- `SourceReadSwift/Core/Import/LocalTextBookParser.swift`
- `SourceReadSwift/Core/Import/LocalTxtSmartDivider.swift`
- `SourceReadSwift/Core/Import/OnboardingClassicBook.swift`
- `SourceReadSwift/Core/Import/SourceImportDownloader.swift`
- `SourceReadSwift/Core/Import/SourceImportLinkParser.swift`
- `SourceReadSwift/Core/Import/XbsBookSourceAdapter.swift`
- `SourceReadSwift/Core/JavaScript/JSCoreRuntime.swift`
- `SourceReadSwift/Core/JavaScript/LegadoCharset.swift`
- `SourceReadSwift/Core/JavaScript/LegadoHostServices.swift`
- `SourceReadSwift/Core/JavaScript/LegadoJavaScriptCompatibility.swift`
- `SourceReadSwift/Core/JavaScript/LegadoModelBridges.swift`
- `SourceReadSwift/Core/JavaScript/LegadoNativeBridges.swift`
- `SourceReadSwift/Core/JavaScript/QueryTTF.swift`
- `SourceReadSwift/Core/Models/BookModels.swift`
- `SourceReadSwift/Core/Models/BookSource.swift`
- `SourceReadSwift/Core/Models/BookshelfModels.swift`
- `SourceReadSwift/Core/Models/BuiltinBrowserSourceProvider.swift`
- `SourceReadSwift/Core/Models/ReadingStatsSummary.swift`
- `SourceReadSwift/Core/Models/SourceCollections.swift`
- `SourceReadSwift/Core/Network/CookieHeaderParser.swift`
- `SourceReadSwift/Core/Network/ResponseBodyDecoder.swift`
- `SourceReadSwift/Core/Network/ResponseTextDecoder.swift`
- `SourceReadSwift/Core/Network/SourcePaginationURLIdentity.swift`
- `SourceReadSwift/Core/Network/SourceRequest.swift`
- `SourceReadSwift/Core/Network/SourceRequestBuilder.swift`
- `SourceReadSwift/Core/Network/SourceURLDirective.swift`
- `SourceReadSwift/Core/Network/SynchronousSourceLoader.swift`
- `SourceReadSwift/Core/Network/SynchronousSourceNetworkBridge.swift`
- `SourceReadSwift/Core/Network/WebDAVSyncService.swift`
- `SourceReadSwift/Core/Network/WebViewFallback.swift`
- `SourceReadSwift/Core/Reader/SmartWebArticleExtractor.swift`
- `SourceReadSwift/Core/Rules/BookDetailParser.swift`
- `SourceReadSwift/Core/Rules/ChapterListParser.swift`
- `SourceReadSwift/Core/Rules/ComicContentParser.swift`
- `SourceReadSwift/Core/Rules/ContentParser.swift`
- `SourceReadSwift/Core/Rules/DynamicURLResolver.swift`
- `SourceReadSwift/Core/Rules/ExploreCategoryParser.swift`
- `SourceReadSwift/Core/Rules/HtmlRuleExtractor.swift`
- `SourceReadSwift/Core/Rules/InlineImageCodec.swift`
- `SourceReadSwift/Core/Rules/JSONRuleExtractor.swift`
- `SourceReadSwift/Core/Rules/LegadoDefaultRuleTranslator.swift`
- `SourceReadSwift/Core/Rules/LegadoRuleAnalyzer.swift`
- `SourceReadSwift/Core/Rules/LegadoRuleResolver.swift`
- `SourceReadSwift/Core/Rules/PurifyRuleEvaluator.swift`
- `SourceReadSwift/Core/Rules/RSSFeedParser.swift`
- `SourceReadSwift/Core/Rules/ResponseFormatDetector.swift`
- `SourceReadSwift/Core/Rules/RuleDirectiveParser.swift`
- `SourceReadSwift/Core/Rules/RuleEditorValidator.swift`
- `SourceReadSwift/Core/Rules/RuleExecutionContext.swift`
- `SourceReadSwift/Core/Rules/RuleOperatorSplitter.swift`
- `SourceReadSwift/Core/Rules/RulePreviewEvaluator.swift`
- `SourceReadSwift/Core/Rules/RuleTransformParser.swift`
- `SourceReadSwift/Core/Rules/SearchBookMatcher.swift`
- `SourceReadSwift/Core/Rules/SearchResultFilter.swift`
- `SourceReadSwift/Core/Rules/SearchResultParser.swift`
- `SourceReadSwift/Core/Rules/SearchURLResolver.swift`
- `SourceReadSwift/Core/Rules/SourceBatchCheckCoordinator.swift`
- `SourceReadSwift/Core/Rules/SourceBatchDiagnosticRunner.swift`
- `SourceReadSwift/Core/Rules/SourceDiagnosticClassifier.swift`
- `SourceReadSwift/Core/Rules/SourceDiagnosticEvidence.swift`
- `SourceReadSwift/Core/Rules/SourceDiagnosticRepairAdvisor.swift`
- `SourceReadSwift/Core/Rules/SourceDiagnosticReport.swift`
- `SourceReadSwift/Core/Rules/SourceDiagnosticReportExporter.swift`
- `SourceReadSwift/Core/Rules/SourceRuleDraft.swift`
- `SourceReadSwift/Core/Rules/VideoContentParser.swift`
- `SourceReadSwift/Core/Rules/XPathRuleTranslator.swift`
- `SourceReadSwift/Core/Security/B18PlusService.swift`
- `SourceReadSwift/Core/Storage/AppDataBackup.swift`
- `SourceReadSwift/Core/Storage/AppStorageDirectory.swift`
- `SourceReadSwift/Core/Storage/BookExportService.swift`
- `SourceReadSwift/Core/Storage/BookshelfGroupPersistence.swift`
- `SourceReadSwift/Core/Storage/BookshelfPersistence.swift`
- `SourceReadSwift/Core/Storage/BookshelfStore.swift`
- `SourceReadSwift/Core/Storage/ChapterContentCacheStore.swift`
- `SourceReadSwift/Core/Storage/ChapterDownloadStore.swift`
- `SourceReadSwift/Core/Storage/CustomFontManager.swift`
- `SourceReadSwift/Core/Storage/InlineImageStore.swift`
- `SourceReadSwift/Core/Storage/PurifyRuleStore.swift`
- `SourceReadSwift/Core/Storage/RSSArticleContentCacheStore.swift`
- `SourceReadSwift/Core/Storage/RSSArticleStateStore.swift`
- `SourceReadSwift/Core/Storage/RSSFeedCacheStore.swift`
- `SourceReadSwift/Core/Storage/ReaderOverrideStore.swift`
- `SourceReadSwift/Core/Storage/ReadingHistoryStore.swift`
- `SourceReadSwift/Core/Storage/SourceCookieStore.swift`
- `SourceReadSwift/Core/Storage/SourceDiagnosticHistoryStore.swift`
- `SourceReadSwift/Core/Storage/SourceHealthStore.swift`
- `SourceReadSwift/Core/Storage/SourcePersistence.swift`
- `SourceReadSwift/Core/Storage/SourceStore.swift`
- `SourceReadSwift/Core/Verification/VerificationCodeCoordinator.swift`

### A.3 Features 层

- `SourceReadSwift/Features/Bookshelf/BookshelfReaderGatewayView.swift`
- `SourceReadSwift/Features/Bookshelf/BookshelfView.swift`
- `SourceReadSwift/Features/Discover/BookDetailView.swift`
- `SourceReadSwift/Features/Discover/ChapterListPresenter.swift`
- `SourceReadSwift/Features/Discover/DiscoverView.swift`
- `SourceReadSwift/Features/Discover/ExploreViewModel.swift`
- `SourceReadSwift/Features/Discover/LightweightHTTPMessage.swift`
- `SourceReadSwift/Features/Discover/SearchBookRow.swift`
- `SourceReadSwift/Features/Discover/SmartWebReaderView.swift`
- `SourceReadSwift/Features/Discover/SourceWritingView.swift`
- `SourceReadSwift/Features/RSS/RSSArticleReaderView.swift`
- `SourceReadSwift/Features/RSS/RSSArticlesView.swift`
- `SourceReadSwift/Features/RSS/RSSReaderSettingsView.swift`
- `SourceReadSwift/Features/Reader/AudioBookPlayerView.swift`
- `SourceReadSwift/Features/Reader/ComicReaderView.swift`
- `SourceReadSwift/Features/Reader/NativeReaderTextView.swift`
- `SourceReadSwift/Features/Reader/PageCurlReaderView.swift`
- `SourceReadSwift/Features/Reader/QuoteCardView.swift`
- `SourceReadSwift/Features/Reader/ReaderAutomationPolicy.swift`
- `SourceReadSwift/Features/Reader/ReaderChapterWindow.swift`
- `SourceReadSwift/Features/Reader/ReaderImageStyle.swift`
- `SourceReadSwift/Features/Reader/ReaderPageLayoutEngine.swift`
- `SourceReadSwift/Features/Reader/ReaderPagedNavigationPolicy.swift`
- `SourceReadSwift/Features/Reader/ReaderPositionMapping.swift`
- `SourceReadSwift/Features/Reader/ReaderSettingsModels.swift`
- `SourceReadSwift/Features/Reader/ReaderView.swift`
- `SourceReadSwift/Features/Reader/VideoPlayerView.swift`
- `SourceReadSwift/Features/Settings/CookieManagerView.swift`
- `SourceReadSwift/Features/Settings/CustomFontManagementView.swift`
- `SourceReadSwift/Features/Settings/PrivacyLegalView.swift`
- `SourceReadSwift/Features/Settings/ReaderDataManagementViews.swift`
- `SourceReadSwift/Features/Settings/SettingsView.swift`
- `SourceReadSwift/Features/Settings/TTSSettingsView.swift`
- `SourceReadSwift/Features/Settings/WebDAVSyncView.swift`
- `SourceReadSwift/Features/SourceManager/RSSSourceEditorView.swift`
- `SourceReadSwift/Features/SourceManager/SourceDiagnosticHistoryView.swift`
- `SourceReadSwift/Features/SourceManager/SourceLoginView.swift`
- `SourceReadSwift/Features/SourceManager/SourceManagerView.swift`
- `SourceReadSwift/Features/SourceManager/SourceRuleEditorView.swift`
- `SourceReadSwift/Features/Verification/VerificationCodeSheet.swift`

### A.4 Shared 层

- `SourceReadSwift/Shared/AppVersion.swift`
- `SourceReadSwift/Shared/HapticFeedback.swift`
- `SourceReadSwift/Shared/ShareSheet.swift`
- `SourceReadSwift/Shared/DesignSystem/AppTheme.swift`
- `SourceReadSwift/Shared/DesignSystem/CachedRemoteImage.swift`
- `SourceReadSwift/Shared/DesignSystem/EmptyStateCard.swift`
- `SourceReadSwift/Shared/DesignSystem/FlowLayout.swift`
- `SourceReadSwift/Shared/DesignSystem/RemoteImageLoader.swift`
- `SourceReadSwift/Shared/DesignSystem/SakuraThemeCatalog.swift`
- `SourceReadSwift/Shared/Diagnostics/DiagnosticEvent.swift`
- `SourceReadSwift/Shared/Diagnostics/DiagnosticSink.swift`
- `SourceReadSwift/Shared/Diagnostics/SourceEngineError+Display.swift`
- `SourceReadSwift/Shared/Foundation/AsyncTimeout.swift`
- `SourceReadSwift/Shared/Foundation/String+SourceRead.swift`
- `SourceReadSwift/Shared/Import/PickedDocumentAccess.swift`
- `SourceReadSwift/Shared/Import/UniversalDocumentPicker.swift`
- `SourceReadSwift/Shared/Performance/FrameRateCoordinator.swift`
- `SourceReadSwift/Shared/Performance/PerformanceSignpost.swift`
- `SourceReadSwift/Shared/Performance/ReaderPerformancePolicy.swift`

### A.5 测试层（124 个 Swift + fixture）

- `SourceReadSwiftTests/AppDataBackupTests.swift`
- `SourceReadSwiftTests/AudioBookPlaybackCoordinatorTests.swift`
- `SourceReadSwiftTests/B18PlusServiceTests.swift`
- `SourceReadSwiftTests/BookSourceTests.swift`
- `SourceReadSwiftTests/BookshelfStoreTests.swift`
- `SourceReadSwiftTests/BuiltinBrowserSourceProviderTests.swift`
- `SourceReadSwiftTests/ChapterContentCacheStoreTests.swift`
- `SourceReadSwiftTests/ChapterDownloadStoreTests.swift`
- `SourceReadSwiftTests/ChapterListMetadataTests.swift`
- `SourceReadSwiftTests/CloudCollectionRuleTests.swift`
- `SourceReadSwiftTests/CloudTTSClientTests.swift`
- `SourceReadSwiftTests/CloudTTSCredentialsTests.swift`
- `SourceReadSwiftTests/CloudTTSFrameTests.swift`
- `SourceReadSwiftTests/CloudTTSProtocolTests.swift`
- `SourceReadSwiftTests/CmbokFeaturesTests.swift`
- `SourceReadSwiftTests/ComicContentParserTests.swift`
- `SourceReadSwiftTests/ContentParserTests.swift`
- `SourceReadSwiftTests/CookieHeaderParserTests.swift`
- `SourceReadSwiftTests/CustomFontAndExportTests.swift`
- `SourceReadSwiftTests/DiscoverViewModelTests.swift`
- `SourceReadSwiftTests/ExploreCategoryParserTests.swift`
- `SourceReadSwiftTests/HaiKuoShiJieSourceAdapterTests.swift`
- `SourceReadSwiftTests/HtmlRuleExtractorTests.swift`
- `SourceReadSwiftTests/HttpTTSClientTests.swift`
- `SourceReadSwiftTests/HuaHuoBookSourceAdapterTests.swift`
- `SourceReadSwiftTests/InlineImagePipelineTests.swift`
- `SourceReadSwiftTests/JSCoreNetworkBridgeTests.swift`
- `SourceReadSwiftTests/JSCoreRuntimeTests.swift`
- `SourceReadSwiftTests/JSONPipelineParserTests.swift`
- `SourceReadSwiftTests/JSONRuleExtractorTests.swift`
- `SourceReadSwiftTests/LegadoAdvancedJsonSourceTests.swift`
- `SourceReadSwiftTests/LegadoCapabilityBankTests.swift`
- `SourceReadSwiftTests/LegadoCharsetTests.swift`
- `SourceReadSwiftTests/LegadoDefaultRuleTranslatorTests.swift`
- `SourceReadSwiftTests/LegadoFixtureTests.swift`
- `SourceReadSwiftTests/LegadoJavaCompatibilityTests.swift`
- `SourceReadSwiftTests/LegadoJavaScriptCompatibilityTests.swift`
- `SourceReadSwiftTests/LegadoNativeBridgeTests.swift`
- `SourceReadSwiftTests/LegadoSourceCapabilityMatrixTests.swift`
- `SourceReadSwiftTests/LegadoStage10CompatibilityTests.swift`
- `SourceReadSwiftTests/LegadoStage18CompatibilityTests.swift`
- `SourceReadSwiftTests/LegadoStage25CompatibilityTests.swift`
- `SourceReadSwiftTests/LegadoStage29CompatibilityTests.swift`
- `SourceReadSwiftTests/LegadoStage9CompatibilityTests.swift`
- `SourceReadSwiftTests/LightweightHTTPMessageTests.swift`
- `SourceReadSwiftTests/LocalEPUBBookParserTests.swift`
- `SourceReadSwiftTests/LocalTextBookParserTests.swift`
- `SourceReadSwiftTests/LocalTxtSmartDividerTests.swift`
- `SourceReadSwiftTests/OnboardingClassicBookTests.swift`
- `SourceReadSwiftTests/PayActionTests.swift`
- `SourceReadSwiftTests/PurifyRuleStoreTests.swift`
- `SourceReadSwiftTests/RSSArticleContentCacheStoreTests.swift`
- `SourceReadSwiftTests/RSSArticleStateStoreTests.swift`
- `SourceReadSwiftTests/RSSFeedCacheStoreTests.swift`
- `SourceReadSwiftTests/RSSFeedParserTests.swift`
- `SourceReadSwiftTests/ReaderAutomationPolicyTests.swift`
- `SourceReadSwiftTests/ReaderChapterWindowPolicyTests.swift`
- `SourceReadSwiftTests/ReaderImageStyleTests.swift`
- `SourceReadSwiftTests/ReaderPageLayoutEngineTests.swift`
- `SourceReadSwiftTests/ReaderPagedNavigationPolicyTests.swift`
- `SourceReadSwiftTests/ReaderPerformancePolicyTests.swift`
- `SourceReadSwiftTests/ReaderPositionMappingTests.swift`
- `SourceReadSwiftTests/ReaderScrollAnchorPolicyTests.swift`
- `SourceReadSwiftTests/ReaderSettingsModelsTests.swift`
- `SourceReadSwiftTests/ReadingHistoryStoreTests.swift`
- `SourceReadSwiftTests/ReadingStatsSummaryTests.swift`
- `SourceReadSwiftTests/ResponseBodyDecoderTests.swift`
- `SourceReadSwiftTests/ResponseFormatDetectorTests.swift`
- `SourceReadSwiftTests/ResponseTextDecoderTests.swift`
- `SourceReadSwiftTests/RuleDirectiveParserTests.swift`
- `SourceReadSwiftTests/RuleEditorRoundTripTests.swift`
- `SourceReadSwiftTests/RuleEditorValidatorTests.swift`
- `SourceReadSwiftTests/RuleExtractorJSTests.swift`
- `SourceReadSwiftTests/RuleOperatorSplitterTests.swift`
- `SourceReadSwiftTests/RulePreviewEvaluatorTests.swift`
- `SourceReadSwiftTests/RuleTransformParserTests.swift`
- `SourceReadSwiftTests/SakuraReaderPaletteTests.swift`
- `SourceReadSwiftTests/SakuraThemeCatalogTests.swift`
- `SourceReadSwiftTests/SandboxEnvironmentTests.swift`
- `SourceReadSwiftTests/SearchBookMatcherTests.swift`
- `SourceReadSwiftTests/SearchResultFilterTests.swift`
- `SourceReadSwiftTests/SearchResultParserExploreTests.swift`
- `SourceReadSwiftTests/SearchResultParserTests.swift`
- `SourceReadSwiftTests/SearchURLResolverTests.swift`
- `SourceReadSwiftTests/SmartWebArticleExtractorTests.swift`
- `SourceReadSwiftTests/SourceBatchCheckCoordinatorTests.swift`
- `SourceReadSwiftTests/SourceBatchDiagnosticRunnerTests.swift`
- `SourceReadSwiftTests/SourceCookieStoreTests.swift`
- `SourceReadSwiftTests/SourceDiagnosticBatchReportTests.swift`
- `SourceReadSwiftTests/SourceDiagnosticClassifierTests.swift`
- `SourceReadSwiftTests/SourceDiagnosticHistoryStoreTests.swift`
- `SourceReadSwiftTests/SourceDiagnosticRepairAdvisorTests.swift`
- `SourceReadSwiftTests/SourceDiagnosticReportExporterTests.swift`
- `SourceReadSwiftTests/SourceDiagnosticReportTests.swift`
- `SourceReadSwiftTests/SourceEngineBodyJSTests.swift`
- `SourceReadSwiftTests/SourceEngineCLevelFixtureTests.swift`
- `SourceReadSwiftTests/SourceEngineCompressedFixtureTests.swift`
- `SourceReadSwiftTests/SourceEngineCryptoFixtureTests.swift`
- `SourceReadSwiftTests/SourceEngineDynamicAjaxFixtureTests.swift`
- `SourceReadSwiftTests/SourceEngineDynamicTokenFixtureTests.swift`
- `SourceReadSwiftTests/SourceEngineFixturePipelineTests.swift`
- `SourceReadSwiftTests/SourceEngineLegadoCorpusTests.swift`
- `SourceReadSwiftTests/SourceEngineMixedResponseFixtureTests.swift`
- `SourceReadSwiftTests/SourceEngineNativeDirectiveTests.swift`
- `SourceReadSwiftTests/SourceEnginePersistentStateTests.swift`
- `SourceReadSwiftTests/SourceEngineStage18FixtureTests.swift`
- `SourceReadSwiftTests/SourceFlowEngineTests.swift`
- `SourceReadSwiftTests/SourceHealthStoreTests.swift`
- `SourceReadSwiftTests/SourceImportDownloaderTests.swift`
- `SourceReadSwiftTests/SourceImportLinkParserTests.swift`
- `SourceReadSwiftTests/SourceMetadataChainTests.swift`
- `SourceReadSwiftTests/SourcePaginationURLIdentityTests.swift`
- `SourceReadSwiftTests/SourcePipelineTests.swift`
- `SourceReadSwiftTests/SourceRequestBuilderDynamicStateTests.swift`
- `SourceReadSwiftTests/SourceRuleDraftStoreTests.swift`
- `SourceReadSwiftTests/SourceStoreTests.swift`
- `SourceReadSwiftTests/SourceURLDirectiveTests.swift`
- `SourceReadSwiftTests/Stage33ReaderExperienceTests.swift`
- `SourceReadSwiftTests/Stage34ComprehensiveParityTests.swift`
- `SourceReadSwiftTests/StubURLProtocol.swift`
- `SourceReadSwiftTests/VerificationCodeCoordinatorTests.swift`
- `SourceReadSwiftTests/VideoContentParserTests.swift`
- `SourceReadSwiftTests/WebDAVSyncServiceTests.swift`
- `SourceReadSwiftTests/XbsBookSourceAdapterTests.swift`
- `SourceReadSwiftTests/Fixtures/legado-capability-bank-20260908.json`
- `SourceReadSwiftTests/Fixtures/legado-cookie-token-source.json`
- `SourceReadSwiftTests/Fixtures/legado-crypto-source.json`
- `SourceReadSwiftTests/Fixtures/legado-dynamic-token-source.json`
- `SourceReadSwiftTests/Fixtures/legado-html-pagination-source.json`
- `SourceReadSwiftTests/Fixtures/legado-html-source.json`
- `SourceReadSwiftTests/Fixtures/legado-java-import-source.json`
- `SourceReadSwiftTests/Fixtures/legado-js-source.json`
- `SourceReadSwiftTests/Fixtures/legado-json-source.json`
- `SourceReadSwiftTests/Fixtures/legado-jxnode-source.json`
- `SourceReadSwiftTests/Fixtures/legado-mixed-response-source.json`
- `SourceReadSwiftTests/Fixtures/legado-post-source.json`
- `SourceReadSwiftTests/Fixtures/legado-stage29-content-page-1.json`
- `SourceReadSwiftTests/Fixtures/legado-stage29-content-page-2.html`
- `SourceReadSwiftTests/Fixtures/legado-stage29-detail.json`
- `SourceReadSwiftTests/Fixtures/legado-stage29-matrix-source.json`
- `SourceReadSwiftTests/Fixtures/legado-stage29-search.html`
- `SourceReadSwiftTests/Fixtures/legado-stage29-toc-page-1.json`
- `SourceReadSwiftTests/Fixtures/legado-stage29-toc-page-2.html`

### A.6 docs

- `docs/2026-06-27-mr-function-absorption.md`
- `docs/APP_STORE_READINESS.md`
- `docs/BUILD.md`
- `docs/IOS-JSON-ECOSYSTEM-DEEP-DIVE.md`
- `docs/JSON-IOS-COMPATIBILITY.md`
- `docs/SOURCE-CAPABILITY-MATRIX.md`
- `docs/legado-js-compatibility-matrix.md`
- `docs/legado-source-capability-table-20260908.md`
- `docs/source-rule-guide.md`
- `docs/stage-20b-acceptance.md`
- `docs/stage-28-acceptance.md`
- `docs/stage-29-acceptance.md`
- `docs/stage-31-acceptance.md`
- `docs/stage-32-acceptance.md`
- `docs/stage-33-acceptance.md`
- `docs/stage-34-acceptance.md`
- `docs/ui-reference-20260907.md`
- `docs/superpowers/plans/2026-09-02-next-major-phase-plan.md`
- `docs/superpowers/specs/2026-06-21-flutter-full-product-audit-and-swift-migration-plan.md`
- `docs/superpowers/specs/2026-06-21-flutter-parity-native-swift-rebuild-design.md`
- `docs/superpowers/specs/2026-06-21-legado-for-mac-reference-audit.md`
- `docs/superpowers/specs/2026-06-21-native-swift-rewrite-design.md`
- `docs/superpowers/specs/2026-06-23-flutter-baseline-read-audit-and-swift-parity-plan.md`
- `docs/superpowers/specs/2026-06-24-swift-v2-lifetime-reader-design.md`
- `docs/superpowers/specs/2026-06-27-flutter-to-swift-parity-ledger.md`
- `docs/superpowers/specs/2026-08-04-legado-javascript-engine-rebuild-design.md`
- `docs/superpowers/specs/2026-09-02-native-ios-performance-and-reader-features-design.md`
- `docs/superpowers/specs/2026-09-06-stage-20a-search-smart-web-design.md`
- `docs/superpowers/specs/2026-09-14-reader-stability-features-design.md`
- `docs/ui-reference/20260907/reference-1.jpg`
- `docs/ui-reference/20260907/reference-2.jpg`
- `docs/ui-reference/20260907/reference-3.jpg`
- `docs/ui-reference/20260907/reference-4.jpg`
- `docs/ui-reference/20260907/reference-5.jpg`
- `docs/ui-reference/20260907/reference-6.jpg`
- `docs/ui-reference/20260907/reference-7.jpg`
- `docs/ui-reference/20260907/reference-8.jpg`

## 附录 B：术语与事实标记约定

### B.1 事实标记

| 标记 | 含义 | 使用场景 |
|---|---|---|
| **已实现** | 仓库内有源码，且有 XCTest、CI 或可复现实测证据 | 功能清单、能力矩阵 |
| **条件支持** | 代码存在，但依赖站点、Cookie、登录、样本或网络环境 | 书源能力 |
| **待验收** | 代码/单测完成，但缺真机或公网验证 | 阅读器、UI、反爬 |
| **未实现** | 明确没有代码路径，或主动不做 | 边界清单 |
| `Observed` | 直接观察到的代码/日志/产物 | 分析结论 |
| `Inferred` | 从代码或行为推断，未直接验证 | 性能、根因 |
| `Assumed` | 假设，需后续验证 | 上游语义、站点行为 |
| `NOT RUN` | 本机/本轮未执行的命令或验收 | 复现步骤 |
| `planned` / `recommended` / `executed` | 计划 / 建议 / 已执行 | 变更记录 |

### B.2 术语

| 术语 | 含义 |
|---|---|
| Legado / 阅读 | Android 开源阅读 App，JSON 书源格式的事实标准 |
| JSON 书源 | 一份 JSON 配置，描述搜索、详情、目录、正文的 URL 与抽取规则 |
| 规则（rule） | `ruleSearch` / `ruleBookInfo` / `ruleToc` / `ruleContent` 下的字段 |
| `@js:` / `<js>` | 规则中的 JavaScript 片段 |
| `java.*` facade | Swift 对 Rhino/Java API 的模拟层 |
| JXNode | Legado 的 DOM 节点包装 |
| JSONPath 方言 | 本项目 `JSONRuleExtractor` 支持的 JSONPath 子集 |
| 窗口（window） | 阅读器同时持有的“当前章 + 前后 N 章” |
| 占位页 | 邻章尚未加载时生成的真实页，用于跨章手势 |
| 章级分页缓存 | 按章保存分页结果，避免邻章回包重排整窗 |
| 读即缓存 | 章节进入阅读位置时刷新 LRU 队首 |
| fixture | 离线书源/HTML/JSON 样本，用于可重复回归 |
| 四件套 | `MODIFIED_FILE` / `DIFF_FILE` / `VERIFICATION.txt` / `ROLLBACK.sh` |
| 三腿验证 | BASELINE → MODIFIED → ROLLBACK 后重跑 |
| L0–L5 | 兼容等级，见 6.5 |
| 未签名 IPA | 未用证书签名的 iOS 安装包，需自签/侧载 |

### B.3 文档维护规则

版本迭代时至少更新：

1. 头部“代码基线 / 验证 Commit / 最新产物”；
2. 第一章 1.2 当前基线表；
3. 第八章版本总表；
4. 第九章本轮工作记录（若为新版本）；
5. 第十章 CI/IPA 证据；
6. 第十一章边界与路线；
7. 第十二章关键提交/运行号；
8. `PROJECT_HANDOVER.md` 对应版本小节。

能力变更时额外更新：

- `docs/SOURCE-CAPABILITY-MATRIX.md`；
- `docs/JSON-IOS-COMPATIBILITY.md`；
- `docs/legado-js-compatibility-matrix.md`；
- 对应 XCTest 与 fixture。

### B.4 证据优先级

```text
真实运行输出 / CI 日志 / IPA 校验
  > 单元测试断言
  > 源码静态阅读
  > 文档描述
  > 推测
```

发生冲突时，以更高优先级为准；文档必须服从事实，而不是让事实迁就文档。

---

> **文档结束**  
> 本文件由本轮工作整理，所有已核实数据来自仓库、Git 历史、GitHub Actions 日志与本地 IPA。  
> 未执行的真机与公网验证均已标注为待验收，未把“代码存在”写成“体验通过”。  
> 下一次更新请从 `PROJECT_HANDOVER.md` 的最新版本小节与 `PROJECT_FULL.md` 第九章开始。
