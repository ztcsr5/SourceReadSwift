# SourceReadSwift (纸间) 项目交接全量备忘录

> **交接目标**：交接给下一位 AI 协作者 / 研发工程师  
> **文档基线**：v1.0.26 (Build 27)  
> **交接时间**：2026-10-24  
> **验证 Commit**：`99db867`（GitHub Actions iOS 932 tests / 0 failures；unsigned IPA 打包通过）  
> **最新产物**：`C:\Users\Edc21\Desktop\SourceReadSwift-1.0.26-unsigned.ipa`（11,343,350 字节，SHA256 `84D1D26C8634F0CD4B264B9414D0DBE8B325E6DA68BF113F4281ACB31BE9A0C3`）

---

## 一、 项目全貌与工作区拓扑 (Project Topology)

### 1. 基础信息
- **应用名称**：纸间 (SourceReadSwift)
- **Bundle ID**：`com.edc21.SourceReadSwift`
- **本地工作区**：`D:\Gemini反重力\SourceReadSwift2`
- **主工作分支**：`codex/swift-v2-lifetime-reader`
- **远端仓库**：`https://github.com/ztcsr5/SourceReadSwift.git`
  - *注：Git remote 已嵌入认证 Token，直接执行 `git push origin codex/swift-v2-lifetime-reader` 即可推送。*
- **当前交付产物**：
  - 路径：`C:\Users\Edc21\Desktop\SourceReadSwift-1.0.26-unsigned.ipa`
  - 大小：`11,343,350 字节 (~10.8 MB)`
  - 验证状态：基于 Commit `99db867`，通过 GitHub Actions CI 真实打包下载（run `40090360203`）；IPA 内 `CFBundleShortVersionString=1.0.26`、`CFBundleVersion=27`、`MinimumOSVersion=16.0`。

### 2. 技术栈架构
- **语言**：Swift 5.9+（全面采用 Swift Concurrency: `async/await`, `actor`, `Sendable`）
- **UI 体系**：SwiftUI + iOS 17 HIG 原生规范，核心排版引擎采用 UIKit TextKit 1 保证极致滚动平滑度与排版控制
- **工程构建**：[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`)
  - 严禁直接手动修改 `.xcodeproj` 文件，新增源文件直接放置于源码目录，配置项与版本号在 `project.yml` 中统一声明，CI 每次自动执行 `xcodegen generate`。
- **依赖库（纯 Swift / 原生）**：
  - `SwiftSoup` (HTML 解析与 DOM 抽取)
  - `ZIPFoundation` (EPUB 解压与归档读写)
  - `CryptoSwift` 与 Apple 原生 `CryptoKit` (密码学哈希、MD5、HMAC-SHA256)
  - 系统 `libz` (Zlib 解压桥接)
  - 原生 `JavaScriptCore` (Legado 规则动态 JS 运行时)

---

## 二、 v1.0.26 核心功能链实现 (What Changed)

`v1.0.22` 完成了书籍插图与漫画排版的完整生命周期闭环；`v1.0.23` 补齐 `ruleContent.payAction` 付费动作链路（第 7 节）；`v1.0.24` 继续补齐 `ruleContent.title` 正文标题回填与 `BookChapter.isPay` 建模，并修复版本元数据漂移（第 8 节）；`v1.0.25` 把未知 `java.*` 调用从 TypeError 降级为可诊断的空值（第 9 节）；`v1.0.26` 把 `ruleContent.imageDecode` 返回的字节负载接入阅读器内联图像管线（第 10 节）。

### v1.0.22 基线：插图与漫画排版

```
SourceRule.ruleContent.imageStyle
       │
       ▼
ContentParser.parseHTML / parseJSON
       │  (提取 imageStyle 规则字符串)
       ▼
ChapterContent (数据模型) & ChapterContentCacheStore (磁盘与内存缓存)
       │  (通过 readerImageStyle 计算属性暴露 ReaderImageStyle 枚举)
       ▼
┌──────────────────────────────────────────────────────────────┐
│                      Reader 双端渲染层                        │
├──────────────────────────────┬───────────────────────────────┤
│    NativeReaderTextView      │          ReaderView           │
│   (滚动模式: TextKit 1)      │     (翻页模式: SwiftUI)       │
├──────────────────────────────┼───────────────────────────────┤
│ • 识别 [img]url[/img] 段落   │ • ReaderIllustrationView      │
│ • 生成 NSTextAttachment 附件 │ • 适配 ReaderImageStyle       │
│ • 占位符绘制与就地排版        │ • FULL/SINGLE 自动撑满列宽    │
│ • RemoteImageLoader 异步加载 │ • DEFAULT 限制 260pt 高度     │
│ • 局部异步重排与偏移位置保活 │ • 点击弹窗查看原图大图        │
└──────────────────────────────┴───────────────────────────────┘
                               ▲
                               │ 透传 Referer / UA 等防盗链请求头
SourceRequestBuilder.imageRequestHeaders(for: currentBookSource)
```

#### 1. 排版策略与尺寸规范 (`ReaderImageStyle.swift`)
- 定义 `ReaderImageStyle` 枚举：`standard` ("DEFAULT")、`full` ("FULL")、`text` ("TEXT")、`single` ("SINGLE")。
- 提供 `ReaderImageSizingPolicy.size(for:style:containerWidth:maximumHeight:)`，精确计算插图在不同设备与排版样式下的显示尺寸。
- 提供 `ReaderImageSizingPolicy.imageURL(in:)`，要求必须具备合法 URI 协议（`scheme != nil`），严防普通文本误识别。

#### 2. 线程安全图文加载器 (`RemoteImageLoader.swift`)
- 替代原有私有 `ImageMemoryCache`，实现全局共享的 `@unchecked Sendable` 内存图片缓存与任务去重器。
- 支持同步读取 `cachedImage(for:)`，在首次 TextKit 渲染命中缓存时直接生成真实图文附件。
- 支持带 Headers 的异步下载 `image(for:headers:)`，合并多处重复请求任务，避免同一张插图并发重复请求。

#### 3. 原生 TextKit 1 滚动排版 (`NativeReaderTextView.swift`)
- `Configuration` 与 `TextLayoutSignature` 扩展支持 `imageStyle`、`imageHeaders` 与 `imageColumnWidth`。
- `ReaderNativeTextLayout` 实现 `replacingImageParagraphs`：
  - 遇到 `[img]url[/img]` 段落时，将其替换为包含 `NSTextAttachment` 的单字符（`\u{FFFC}`）属性字符串。
  - 使用逆序遍历更新后续段落 ranges 的 location 偏移，确保段落级语音高亮（TTS）与行数映射不受破坏。
  - 图片未缓存时绘制轻量优雅的圆角卡片与相框占位图；图片加载完成后自动通知 Coordinator 重新计算并保持视口偏移平稳。

#### 4. 翻页模式全宽渲染 (`ReaderView.swift`)
- 提取专门的 `ReaderIllustrationView` 组件，根据 `currentImageStyle.stretchesToColumnWidth` 自动切换全宽或限高渲染。
- 在 `scrollReaderContent` 中向 `NativeReaderTextView` 传入实时的 `imageStyle`、`imageHeaders` 与列宽。

#### 5. 防盗链请求头透传 (`SourceRequestBuilder.swift`)
- 新增 `imageRequestHeaders(for source: BookSource) -> [String: String]`。
- 自动提取书源配置的 User-Agent、Cookie 与自定义 header，并补充符合源域名的 `Referer` 与标准图片 `Accept`，确保 CDN 图片不被防盗链拦截。

#### 6. 多页章节续接保活 (`SourceEngine.swift`)
- 章节分页合并时，在最终的 `ChapterContent` 初始化中传递 `imageStyle: firstPage.imageStyle`，避免后续分页丢失排版指令。

### 7. 付费动作 `payAction` 全链路 (`PayActionPolicy.swift` / `SourceEngine.swift` / `ReaderView.swift`)
- **入口**：`ruleContent.payAction` 随 `ChapterContent` 透传；阅读器菜单仅在 `loginUrl` / `loginCheckJs` 存在、`chapter.isVip == true`、`payAction` 非空时显示「购买本章」。
- **确认**：`confirmationDialog` 标题为「购买本章」，message 为章节标题，对齐 Legado `ReadBookActivity.payAction()`。
- **求值**：`PayActionPolicy` 先判断纯 `http(s)://` 并直接打开，不把 URL 喂给 JavaScriptCore；`{{…}}` 模板逐段求值；`@js:` / `<js>` 走同一 `RuleExecutionContext`（Cookie、持久变量、同步网络桥、诊断 stage `payAction`）。
- **结果分类**：绝对 URL → `UIApplication.open`；Legado `isTrue` 真值（`ok` / `success` / 中文等）→ `.purchased`；`false/no/not/0/空/null` → `.failed` 并提示，不伪造成功。
- **购后**：先 `ChapterContentCacheStore.invalidate(sourceURL:chapter:)`，再 `onRefreshChapter?()`；对应 Legado `delContent` + `loadChapterList`。
- **模型**：`chapter` JS 变量补齐 `title` / `name` / `url` / `chapterUrl` / `bookUrl` / `index` / `chapterIndex` / `isVip` / `updateTime` / `volumeName` / `wordCount`；布尔 `isVip` 不再被标题启发式覆盖。
- **`isPay`**：v1.0.24 已建模（第 8 节），按钮条件为 `hasLogin && isVip && isPay != true`。
- **回归**：`PayActionTests` 18 个用例 + `JSCoreRuntimeTests.testChapterBooleanIsVipSurvivesFallbackInjection`；v1.0.23 基线 CI 915 tests / 0 failures。

### 8. v1.0.24 增量：正文标题回填、`isPay` 建模与版本元数据单一来源

- **`ruleContent.title`**：`ContentParser` 在正文 HTML / JSON 响应上执行 title 规则。HTML 在 document root 上求值（兼容 `<h1>` 位于正文容器之外），JSON 走 `title/chapterName/name` 回退键；空值或规则失败回退目录标题。`ChapterContent.title` 承载正文标题，`chapter.title` 保持目录标题不变。
- **`BookChapter.isPay`**：新增 `Bool?`（旧缓存缺失解码为 `nil` = 未知）；目录 HTML / JSON 独立解析 `isPay/paid/purchased`，不再把 `isPay` 误当 `isVip`；`withIndex` / `withTitle` / 缓存 / JS bridge 全链透传。
- **购买按钮**：`canShowPayAction` 改为 `hasLogin && isVip && isPay != true`，已购章节不再重复显示「购买本章」。
- **JS 变量**：`payAction` 的 `chapter.isPay` 暴露为布尔值（`nil` 投影为 `false`），Legado 源规则可直接分支。
- **版本元数据**：`project.yml` 的 `info.properties` 改为 `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`；Unsigned IPA workflow 增加 `PlistBuddy` 断言，IPA 内部版本与 `project.yml` 不一致时 CI 直接失败。该断言发现并修复了首次 1.0.24 打包内部仍是 1.0.23/24 的漂移。
- **回归**：`ChapterListMetadataTests` 3 个（HTML `isPay` 独立解析、JSON 布尔/字符串/缺省、旧缓存 Codable）、`ContentParserTests` 4 个（HTML/JSON title、CSS miss 回退、`@js:` title）、`JSCoreRuntimeTests` 1 个（`chapter.isPay` 布尔）；CI 923 tests / 0 failures。

### 9. v1.0.25 增量：未知 `java.*` 调用的可控降级与诊断

- **问题**：书源脚本调用本 build 尚未实现的 `java.*` 方法时，JS 侧拿到 `undefined`，调用即抛 TypeError，整条目录/正文规则直接失败，用户只看到空章节。
- **实现**：prelude 末尾安装 `java = new Proxy(java, ...)`。未知成员返回函数，转交 `__nativeLegado.invoke`；原生 dispatcher 记录 `bridge.error java.<name>: unsupported host method` 并返回空串，规则其余部分继续执行。
- **顺序约束**：代理必须在 prelude 末尾安装。prelude 内部存在 `java.jsoup = java.jsoup || {...}` 这类惰性命名空间初始化；过早代理会让 `java.jsoup` 变成 truthy 函数，跳过初始化，导致 `select` / `getAttr` 崩溃（`99c707c` 因此 1 个用例失败）。
- **诊断**：`bridge.error` 行进入 `RuleExecutionContext.logs()`，随 `SourceDiagnosticEvidence.executionLogs` 导出，源诊断面板可见。
- **回归**：`JSCoreRuntimeTests.testUnknownJavaMethodDegradesAndRecordsBridgeDiagnostic`（未知 API 返回空串且写入 bridge.error）、`testUnknownJavaMethodProxyKeepsKnownBridgesWorking`（已实现方法不被代理覆盖）；CI 925 tests / 0 failures（v1.0.25 时点）。

### 10. v1.0.26 增量：`ruleContent.imageDecode` 字节负载的内联图像管线

- **问题**：Legado 源在反爬/拼图场景下，`imageDecode` 可能不返回替换 URL，而是返回 `data:image/...;base64,...`、裸 base64、`java.ajaxBytes` 的 `byte[]`（JS 侧表现为 JSON 数组），或数字键对象 `{"0":137,...}`。此前实现只覆盖 URL 重写，这类源在 iOS 上正文插图直接缺失。
- **解码**：新增 `InlineImageCodec`。`InlineImageDecoder.decode` 识别四种负载形态，按文件魔数确认 png/jpg/gif/webp/bmp/tiff/heic/avif，单图上限 32 MB；普通 URL 与任意 JSON 规则输出返回 `.notInline`，继续走原有绝对化路径，保证零回归。
- **落盘**：新增 `InlineImageStore`。解码后的字节写入应用支持目录，段落只保存 `srdata://inline/<sha256>.<ext>` 令牌；同内容去重，令牌正则拒绝路径穿越，目录总量 256 MB 上限并在超限时裁到 75%，目录标记为不进入 iCloud 备份。
- **渲染**：`ContentParser` 在 `applyingImageDecode` 中把 `.decoded` 写入注册表、把段落重写为 `[img]srdata://...[/img]`；`RemoteImageLoader` 首段识别 `srdata`，读盘后在后台线程 `UIImage(data:)?.preparingForDisplay()`，复用同一 NSCache。非法负载只记日志并保留原图 URL，不丢插图。
- **设计取舍**：不直接把裸 `data:` URI 写进段落。原因有三：段落长度会从约 110 字符膨胀到数十 KB（撑大 `ChapterContentCacheStore`）；`+ / =` 需要转义；`URLSession` 本身不能加载 `data:` URL。注册表令牌同时解决去重与缓存键问题。
- **回归**：`InlineImagePipelineTests` 7 个用例——四种解码形态、拒绝非图像与普通 URL、data URI 入库且段落紧凑、`java.ajaxBytes` → `RemoteImageLoader` 真实解码 3×2 像素、非法 base64 保留原 URL、越界字节数组保留原 URL、store 去重与路径穿越；CI 932 tests / 0 failures。
- **边界**：本次覆盖“单次规则输出即完整图片”。若某个源把拼图切片分多次返回、需要按坐标拼成一张位图，仍属于后续 Canvas 拼图能力，不在本版范围。

---

## 三、 代码路径与核心文件索引 (Where it lives)

| 模块 | 核心源码物理路径 | 作用与责任 |
|---|---|---|
| **排版样式** | `SourceReadSwift/Features/Reader/ReaderImageStyle.swift` | 样式枚举解析、几何尺寸计算、URL 校验 |
| **图片加载** | `SourceReadSwift/Shared/DesignSystem/RemoteImageLoader.swift` | 全局图片内存缓存、并发请求去重、异步解码；识别 `srdata://` 内联图令牌并复用同一缓存 |
| **图片视图** | `SourceReadSwift/Shared/DesignSystem/CachedRemoteImage.swift` | 视图层图片组件，支持请求头透传与尺寸回调 |
| **原生阅读器** | `SourceReadSwift/Features/Reader/NativeReaderTextView.swift` | TextKit 1 排版、NSTextAttachment 内联、异步重排 |
| **翻页阅读器** | `SourceReadSwift/Features/Reader/ReaderView.swift` | 阅读器页面组装、插图视图、请求头采集 |
| **请求构建器** | `SourceReadSwift/Core/Network/SourceRequestBuilder.swift` | 图片防盗链 Header 构建（Referer / UA） |
| **正文解析器** | `SourceReadSwift/Core/Rules/ContentParser.swift` | 从 HTML / JSON 规则中提取 `imageStyle`；把 `imageDecode` 字节负载写入内联图注册表 |
| **内联图解码** | `SourceReadSwift/Core/Rules/InlineImageCodec.swift` | 四种 `imageDecode` 负载形态识别、魔数校验、32 MB 上限 |
| **内联图存储** | `SourceReadSwift/Core/Storage/InlineImageStore.swift` | `srdata://` 注册表、SHA256 去重、256 MB 裁剪、排除 iCloud 备份 |
| **内联图测试** | `SourceReadSwiftTests/InlineImagePipelineTests.swift` | 7 个用例：解码形态、入库、真实 UIImage 解码、坏负载回退、去重与路径穿越 |
| **正文模型** | `SourceReadSwift/Core/Models/BookModels.swift` | `ChapterContent.imageStyle` 模型与向下兼容构造器 |
| **缓存持久化** | `SourceReadSwift/Core/Storage/ChapterContentCacheStore.swift` | 章节正文磁盘/内存缓存条目扩展 |
| **单元测试** | `SourceReadSwiftTests/ReaderImageStyleTests.swift` | 样式解析、几何计算、图文附件与请求头全量测试 |
| **付费动作策略** | `SourceReadSwift/Core/Engine/PayActionPolicy.swift` | 纯 URL / 模板 / JS 求值与 `isTrue` 分类 |
| **付费动作测试** | `SourceReadSwiftTests/PayActionTests.swift` | 18 个 `payAction` 用例：求值、分类、缓存、Codable |
| **文档基线** | `docs/JSON-IOS-COMPATIBILITY.md` & `docs/SOURCE-CAPABILITY-MATRIX.md` | 能力矩阵与 iOS 兼容边界同步更新 |
| **正文标题** | `SourceReadSwift/Core/Rules/ContentParser.swift` | `ruleContent.title` HTML/JSON 求值与回退 |
| **章节付费标记** | `SourceReadSwift/Core/Models/BookModels.swift` | `BookChapter.isPay` 可选字段与全链透传 |
| **JS 兼容降级** | `SourceReadSwift/Core/JavaScript/JSCoreRuntime.swift` | 未知 `java.*` 调用经 Proxy 降级并写入 `bridge.error` 诊断 |
| **工程配置** | `project.yml` & `SourceReadSwift/App/Info.plist` | 版本声明（1.0.26 / Build 27）；bundle 版本由 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 单一来源派生 |

---

## 四、 验证结果与 CI 证据 (How to verify)

### 1. 自动化测试结果
- **GitHub Actions Run ID**：`40090360201`
- **Job ID**：`120861597916`
- **验证 Commit**：`99db867`
- **运行结论**：`Success`
- **用例总数**：**932 个 XCTest 单元测试全部通过（0 failures, 0 unexpected）**
- **本轮新增/关键覆盖**：
  - 新增 `InlineImagePipelineTests` 7 个用例：`testInlineImageDecoderRecognizesDataURIByteArrayAndRawBase64`、`testInlineImageDecoderRejectsNonImageAndOrdinaryURLs`、`testImageDecodeStoresInlineDataURIAndKeepsParagraphCompact`、`testImageDecodeReadsAjaxBytesAndLoadsThroughRemoteImageLoader`、`testImageDecodeRejectsMalformedInlinePayloadAndKeepsOriginalURL`、`testImageDecodeRejectsOutOfRangeByteArrayAndKeepsOriginalURL`、`testInlineImageStoreDeduplicatesAndRejectsTraversal`
  - v1.0.25 的 `JSCoreRuntimeTests.testUnknownJavaMethodDegradesAndRecordsBridgeDiagnostic`、`testUnknownJavaMethodProxyKeepsKnownBridgesWorking` 继续通过
  - v1.0.24 的 `ChapterListMetadataTests` / `ContentParserTests` / `JSCoreRuntimeTests.testChapterBridgeExposesIsPayAsBoolean` 继续通过
  - `PayActionTests` 18 个用例继续通过
  - `SearchURLResolverTests.testAppVersionSemantics` 锁定 1.0.26 / Build 27
- **历史失败记录（v1.0.25）**：`99c707c` 首版代理在 prelude 中部安装，破坏 `java.jsoup = java.jsoup || {...}`，run `40085678639` 出现 1 failure；`0b46689` 将代理移到 prelude 末尾后全绿。

### 2. IPA 打包产物
- **GitHub Actions Run ID**：`40090360203`
- **产物名**：`SourceReadSwift-unsigned-ipa`
- **本地落盘路径**：`C:\Users\Edc21\Desktop\SourceReadSwift-1.0.26-unsigned.ipa`
- **产物大小**：`11,343,350 字节`
- **SHA256**：`84D1D26C8634F0CD4B264B9414D0DBE8B325E6DA68BF113F4281ACB31BE9A0C3`
- **Info.plist 核验**：`CFBundleShortVersionString=1.0.26`、`CFBundleVersion=27`、`MinimumOSVersion=16.0`（workflow 内 `PlistBuddy` 断言强制校验）

---

## 五、 后续演进建议与未尽事项 (Next Steps for AI)

下一位接手的工程师或 AI 可在此坚实基准上推进以下事项：

1. **`imageDecode` 后续（P2，非阻塞）**：
   - v1.0.26 已覆盖“一次返回完整图片”的四类负载（data URI、裸 base64、`byte[]` JSON 数组、数字键对象），并完成落盘、去重、渲染与坏负载回退。
   - 仅剩“源分多次返回切片、客户端按坐标拼成一张图”的 Canvas 拼图场景；这需要真实的切片样本才能定义坐标系，禁止凭猜测实现。
2. **`downloadUrls`（P2，已决策）**：
   - 当前既不解析该字段，也不渲染下载入口，因此不存在“可点但无反应”的死按钮。
   - 若后续实现，前提是完整下载队列、进度、失败重试与文件管理一起交付；只加一个入口不加队列属于半成品，不做。
3. **目录逐章字数（已完成，文档已校正）**：
   - `ChapterListPresenter.metadataLabel` 已在 `BookDetailView` 的紧凑目录与完整目录两处渲染，输出 `更新 <时间> · <字数>`；`ChapterListMetadataTests` 与 `SourceMetadataChainTests` 覆盖 `3200字`、`1.2万字` 与单侧缺省。
4. **`nextContentUrl` 多值 / `replaceRegex` 合并顺序（P2，语义待固定）**：
   - 这两项都依赖上游 Legado 的精确执行语义；当前上游源码不可访问，先不写“猜测式兼容”。
   - 正确顺序：找到可复现的真实源 → 固化为离线 fixture → 记录期望输出 → 再改执行位置，并保证单 URL 源零回归。
5. **上游参考实现消失的长期影响（2026-10-24 实测）**：
   - `gedoor/legado` 主仓库内容已被作者删除，GitHub API 的默认分支只剩 README 与公告图片；无法再在线对照 Kotlin 实现或拉取最新规则语义。
   - 因此兼容性基线必须固定在仓库内：`SourceReadSwiftTests/Fixtures/legado-capability-bank-20260908.json`（13 源快照）+ 各阶段离线 fixture。任何“按上游最新代码对齐”的计划都要改为“按冻结样本对齐”。
