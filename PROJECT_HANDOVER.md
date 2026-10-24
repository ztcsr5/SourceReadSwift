# SourceReadSwift (纸间) 项目交接全量备忘录

> **交接目标**：交接给下一位 AI 协作者 / 研发工程师  
> **文档基线**：v1.0.29 (Build 30)  
> **交接时间**：2026-10-25  
> **验证 Commit**：`7773e2b`（GitHub Actions iOS 984 tests / 0 failures；unsigned IPA 打包通过）  
> **最新产物**：`C:\Users\Edc21\Desktop\SourceReadSwift-1.0.29-unsigned.ipa`（11,466,987 字节，SHA256 `C2CC7A38778A76338E6BDA61BC14D0E75BF908A88C7F72485D06368CF6AD8D2A`）

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
  - 路径：`C:\Users\Edc21\Desktop\SourceReadSwift-1.0.29-unsigned.ipa`
  - 大小：`11,466,987 字节 (~10.9 MB)`
  - 验证状态：基于 Commit `7773e2b`，通过 GitHub Actions CI 真实打包下载（run `40109182535`）；IPA 内 `CFBundleShortVersionString=1.0.29`、`CFBundleVersion=30`、`MinimumOSVersion=16.0`。

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

## 二、 核心功能链实现（v1.0.22 → v1.0.29） (What Changed)

`v1.0.22` 完成了书籍插图与漫画排版的完整生命周期闭环；`v1.0.23` 补齐 `ruleContent.payAction` 付费动作链路（第 7 节）；`v1.0.24` 继续补齐 `ruleContent.title` 正文标题回填与 `BookChapter.isPay` 建模，并修复版本元数据漂移（第 8 节）；`v1.0.25` 把未知 `java.*` 调用从 TypeError 降级为可诊断的空值（第 9 节）；`v1.0.26` 把 `ruleContent.imageDecode` 返回的字节负载接入阅读器内联图像管线（第 10 节）；`v1.0.27` 修复阅读器三模式与阅读界面；`v1.0.28` 把四模式阅读器改成双向跨章窗口（第 12 节）；`v1.0.29` 把预取改成近邻优先的串行队列，并修正向后翻页落到上一章章尾（第 13 节）。

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

### 11. v1.0.27 增量：阅读器三模式与阅读界面整改

本轮起点是 `51b57fe`（页模型与分页切页的修正版本，CI 963 tests 绿），交付 `bb46349`。范围只覆盖阅读链路：分页页模型、连续滑动、覆盖翻页、系统卷曲翻页、阅读界面顶/底栏与设置面板、目录/书签跳转、漫画阅读器。所有条目均为读码定位的真实缺陷，没有凭猜测改行为。

#### A. 分页页模型（三种翻页共用）

1. **页数与视觉不符、长段溢出**：`buildReaderPageBlocks` 原来按估算行高切页。改为 TextKit `NSLayoutManager` 取真实行片段测量；长段按真实行续切；标题先测高。`ReaderPageLayoutEngine.split` 对每个 chunk 重新 `measureHeight` 并预留 4pt 余量，消除 167 vs 159、587 vs 579 这类累计误差（首版 CI 的 4 个失败即此）。
2. **纯标题页丢失导致末页不可达**：`ReaderPositionMapping` 用 `compactMap` 过滤无正文页后，页索引整体偏移。新增 `pageStarts(from: [Int?])` 保留占位页，`ReaderView` 两处映射改用该入口。
3. **模式切换/字体变化越界**：`rebuildPagedBlocksCache` 统一用 `ReaderPagedNavigationPolicy.clampedTargets` 同时收敛页索引与段索引；`progressTitle` 与章节 Slider 目标值一并 clamp。
4. **插图页预算不足**：只预留位图高度，说明文字与卡片内边距会溢出到页脚。新增 `pagedCaptionHeight = 44`，按整卡 `cardHeight` 参与预算；`ReaderImageSizingPolicy.imageURL` 先 `trimmingCharacters`，段落前后有空白也能识别插图。
5. **页内滚动与翻页手势打架**：分页页去掉 `ScrollView`，改为固定 `VStack` + `.clipped()`，一页只响应翻页手势。

#### B. 连续滑动模式（默认模式）

6. **点击区域只有中间"菜单"有效**：`runTapAction` 在 `readerMode == .scroll` 时只处理 `.menu` 并直接 `return`，而默认九宫格的左右/上下区域全是"上一页/下一页"——用户侧表现就是"滑动模式坏了、点哪都没反应"。新增 `ReaderPageStepPolicy`：一屏步进 `1 - 12%` 重叠（不漏行）、`adjustedContentInset` 感知的上下边界收敛、边界判定；`NativeReaderTextView.applyPageStep` 以 280ms ease-out 执行并刷新可见段；到顶/到底再点翻页通过 `onPageStepBoundary` 交给上一/下一章。
7. **追加章节错章**：网络追加任务在用户切章后仍会把旧"下一章"写进新章。任务记录 `originChapterIndex`，回包校验章号、列表上限与重复后才 append；缓存分支同样受 `isAppendingNextChapter` 与 `last.chapterIndex` 防护。
8. **滑动自激抖动**：可见段回调反向写 `scrollParagraphTarget` 会触发滚动请求循环。回调只更新 `visibleParagraphIndex`；跳转统一走 `scrollJumpGeneration`，`scrollToParagraph` 增加 `!isDecelerating` 保护。

#### C. 覆盖翻页

9. **过半不翻、回弹错误、连划丢页**：新增 `ReaderCoverSwipePolicy`，用 `predictedEndTranslation` + 18% 宽度阈值 + 轴向/边界裁剪判定；松手 340ms 动画结束后以 `Transaction(disablesAnimations)` 提交页索引，动画期间忽略新手势。

#### D. 系统卷曲（仿真）翻页

10. **目录/TTS/跳转与卷曲动画竞争、字号变化显示旧页**：`PageCurlReaderView` 增加 `contentRevision` 与 `ReaderPageCurlSyncPolicy`——用户交互中不抢动画，revision 变化才 reload；首次进入白屏由索引 clamp + 空页处理修复。

#### E. 阅读界面（顶栏/底栏/设置）

11. **顶栏图标挤压标题**：刷新/缓存/购买/详情/换源收进 `Menu`；标题 `minimumScaleFactor(0.78)` + `layoutPriority(1)`。
12. **章节 Slider 拖动中每格换章**：改为 draft 值，`onEditingChanged` 结束时才 `selectChapter`。
13. **睡眠定时徽标挤乱工具栏**：改为挂在"设置"按钮上的 overlay 徽标。
14. **横屏设置面板被裁**：`max(h*0.84, 560)` 在 390pt 高的横屏超出可视区，关闭按钮不可见。新增 `ReaderSettingsLayoutPolicy.maxPanelHeight(viewportHeight:bottomInset:)`（390/21 → 345，844/34 → 709，667/0 → 560）。
15. **设置缺项**：高级页补自动滚动间隔滑块；外观页补亮度卡片与"跟随系统"；`applyReaderBrightness` 在 `readerBrightness < 0` 时恢复进入阅读器前的亮度。
16. **底部预留带一直空白**：`footerHeight`（默认 72pt）在所有模式都给正文让了位，但全屏阅读没有时间、电量、进度。新增 `readerFooter`：`TimelineView(.everyMinute)` 时间 + `progressTitle` + `UIDevice` 电量/充电图标；仅在 chrome 隐藏且无朗读/自动滚动时显示，`allowsHitTesting(false)`；进入阅读器开启电量监测、退出关闭。
17. **跨章书签只跳到章首**：目录与书签统一 `canJumpToChapter`，优先调用 `onSelectChapterWithPosition`，跨章书签直接落到记录段；只有位置无关回调时才退回 `onSelectChapter`。

#### F. 漫画阅读器

18. **切章竞态**：慢源回包会覆盖后打开章节的页面。新增 `loadGeneration` 令牌；切章同时清空 `pages`，加载态与错误态都能正常出现。
19. **首页/末页第二次点击无效**：`scrollTargetIndex` 残留旧值，SwiftUI diff 认为无变化。滚动执行后清空请求，切章也清空。
20. **下一章继承上一章缩放**：TabView 复用页面视图，`scale/lastScale` 未重置。`url` 变化时复位缩放。

#### G. 验证

- 新增 `ReaderPageStepPolicy` 5 个用例（一屏步进、上下边界、inset、boundary、短内容不动）+ 设置面板高度 1 个用例；`ReaderPageLayoutEngineTests` 14 个用例、`ReaderPagedNavigationPolicyTests` 其余用例继续通过。
- CI：iOS run `40096362239` / job `120879785198`，**969 tests / 0 failures / TEST SUCCEEDED**（基线 `51b57fe` run `40095125227` 为 963 tests）。
- IPA：run `40096362252` / job `120879342208`，`SourceReadSwift-1.0.27-unsigned.ipa`，11,390,330 字节，SHA256 `3A7BE269E3F6CBDFEC0EED159BE7194A02CC3D7F7FD7F348F8CAF7F86A866371`，Info.plist 1.0.27 / Build 28 / iOS 16.0。
- 四件套与三段验证（基线 / 修改 / 反向补丁回滚）落在 `E:\codex-temp\sourceread\artifacts\reader-modes-v27\`；回滚后 7 个文件与基线逐字节一致。

### 12. v1.0.28 增量：双向跨章窗口、无限前后翻与预缓存

本轮起点是 v1.0.27（`1790d44`），目标是把“读完一章再手动点下一章”改成主流阅读器的连续阅读模型。核心不是某个手势，而是把阅读器从“单章内容 + 单章页码”改成“当前章 + 前后各 N 章的连续窗口”。

#### A. 窗口模型

1. 新增 `ReaderChapterWindow.swift`：
   - `ReaderChapterSection` 表示窗口中一章的标题、段落和加载状态；
   - `ReaderChapterWindowPolicy` 负责窗口半径、最近优先的预取顺序、书籍边界裁剪、加载中章节保留、扁平段落布局和跨章页索引解析；
   - `retainedIndices` 保留当前章 + 半径内章节 + 正在加载章节，避免慢源回包时把目标章提前淘汰；
   - `prefetchOrder` 永远排除当前章，按距离最近、同距离优先向后的顺序预取。
2. `ReaderView` 以 `windowSections` 作为唯一阅读窗口：
   - 初始 `seedWindow()` 放入当前章，并立即预热前后章节；
   - `prefetchWindow` 随当前章变化继续补齐两侧；
   - `trimWindowIfNeeded` 只收缩内存窗口，不删除磁盘缓存；已经读过的章节再次进入窗口时直接命中 `ChapterContentCacheStore`，不会重新请求；
   - `windowGeneration` 令牌丢弃切章/重置前的过期回包。
3. 缓存链：本地章节 → `ChapterContentCacheStore` 磁盘缓存 → `SourceEngine.getContent` 网络请求（12 秒超时）→ 写回缓存。滚动、覆盖、平移、仿真四种模式共用同一条章节加载链。
4. `BookDetailView` 的预取改为“前 N 章优先、后 N 章随后”，跳过已缓存章节；“缓存前后章节”菜单按阅读器当前章发起，不再固定缓存打开阅读器时的章节。

#### B. 连续滑动（TextKit 模式）

- `scrollModeParagraphs` 把所有已加载章节拼成一个扁平段落空间，章间插入标题分隔段；`windowLayout` 用同一套规则计算章节起点。
- 向上预取到上一章时，`NativeReaderTextView` 用字符锚点 + `ReaderScrollAnchorPolicy.paragraphShift` 精确恢复视口，不会因为前面插入整章而跳到章首。
- 向下预取时走快速 append，不重建整块 TextStorage；`onNearTop/onNearBottom` 提前触发两侧预取，`onReachTop/onReachBottom` 负责边界兜底。
- 点击区域的上一页/下一页仍通过 `ReaderPageStepPolicy` 在扁平空间中步进；到边界后由窗口继续加载，不再依赖外层“切章”回调。

#### C. 覆盖、平移、仿真三种分页模式

- `buildReaderPageBlocks` 现在按整个窗口分页，每章保留自己的标题页；章与章之间不再重置页码。
- 未加载的相邻章会生成真实占位页，因此 TabView、覆盖拖动和 `UIPageViewController` 都能滑过章边界进入“正在加载”页，而不是在 `count - 1` 回弹。
- `ReaderPageBlock` 增加章节归属、章内页序号 `pageOrdinal`、占位方向；`ReaderChapterPosition` 带上 `pageOrdinal`，用于在窗口插入/删除章节后保持精确页。
- `ReaderView` 的 `pagedPageIndex` 是全局连续页索引；`updatePagedVisibleParagraph` 在占位页触发对应章节加载，章节回包后由 `restoredPageIndex` 落回该章第一页。
- 覆盖模式维持 `ReaderCoverSwipePolicy` 的速度/位移判定；平移模式由 TabView 原生分页；仿真模式由 `PageCurlReaderView` 的 revision 同步策略在加载完成后原位替换占位页。

#### D. 本轮修复的边界缺陷

1. `retainedIndices` 在空书/越界章号时会返回不存在的索引，导致窗口裁剪崩溃或加载不存在的章节；已按 `lowerBound/upperBound` 过滤。
2. 滚动兜底路径把扁平段落索引误当成章节内段落索引；已统一转换为 `ReaderChapterPosition` 后再落盘/定位。
3. 内容刷新时旧页码可能落到新章节的错误页；`rebuildPagedBlocksCache(useCachedPageAnchor:)` 在内容变更和模式切换时从实时阅读位置重建，避免复用失效的 `pageOrdinal`。
4. 预取窗口变化时 TextKit 的字符锚点会因前置章节插入而漂移；已用窗口差异位移恢复行位置。
5. 音频朗读和自动滚动跨章时不再销毁阅读器：窗口命中则原位续播/续滚，缺章则先进入 pending 状态，章节到达后恢复。

#### E. 验证

- 新增/更新测试：
  - `ReaderChapterWindowPolicyTests`：章节边界、预取顺序、加载中保留、扁平布局、页占位解析；
  - `ReaderScrollAnchorPolicyTests`：前置插入/追加/裁剪的字符锚点位移；
  - `ReaderSettingsModelsTests`：预加载标题改为“前后各 N 章”；
  - `SearchURLResolverTests.testAppVersionSemantics`：锁定 1.0.28 / Build 29。
- CI：iOS run `40107402912` / job `120911836046`，commit `285950e`，**983 tests / 0 failures / TEST SUCCEEDED**。
- IPA：run `40107402785` / job `120911835560`，产物 `C:\Users\Edc21\Desktop\SourceReadSwift-1.0.28-unsigned.ipa`，11,462,716 字节，SHA256 `AA382E773C727F9FD95EDA3FF51AFA6554B85E939780DF6779CE4EDB8BA96402`；Info.plist 复验 1.0.28 / Build 29 / iOS 16.0 / `com.edc21.SourceReadSwift`。
- 四件套：`E:\codex-temp\sourceread\artifacts\reader-continuous-v28\`（`BASELINE/`、`MODIFIED/`、`DIFF.patch`、`ROLLBACK.sh`、`VERIFICATION.txt`）；回滚在独立副本上执行，12 个文件恢复后与 v1.0.27 基线逐字节一致，新增文件被删除。

**仍待真机验证**：四种模式的连续手势节奏、覆盖动画与预取回包同时发生时的视觉稳定性、超长章节窗口裁剪后的回翻体验。当前环境没有 Xcode/真机，这些只能由 CI 编译 + 单元测试覆盖，不能把“未真机点击”写成“已通过”。

### 13. v1.0.29 增量：串行预取与向后翻页落章尾

本轮起点是 v1.0.28（`285950e`），只修跨章阅读链路的两个真实缺陷，不改书籍解析与设置数据格式。

#### A. 预取乱序会在章界制造空洞

v1.0.28 的 `prefetchWindow` 对窗口内所有缺失章节同时发起请求。近邻章节 N+1 与更远的 N+2 竞争网络，N+2 可能先返回；页面模型于是先出现 N+2，再在 N+1 的位置留下占位页。用户正好跨章时会看到“正在加载下一章”，与“提前缓存前后”的目标相反。

#### B. 串行队列与直接请求抢占

- `ReaderView` 新增 `prefetchQueue` / `prefetchTask` / `prefetchGeneration`。
- `queuePrefetch` 按 `ReaderChapterWindowPolicy.prefetchOrder` 的“最近优先、同距离向后优先”顺序逐章加载；一次只发一个请求，远处的章节不可能越过近邻先完成。
- `requestChapter` 走 `loadWindowChapter` 直接加载用户当前需要的章节，队列通过 `windowLoadingIndices` 自动跳过，保证“用户点到的章”永远优先于后台预取。
- `resetWindow` / `seedWindow` / `onDisappear` 调用 `cancelPrefetch`，用 `windowGeneration` 与 `prefetchGeneration` 双重令牌丢弃旧回包，避免切书或切章后旧请求污染新窗口。
- 预加载设置调大（最多前后各 5 章）时，也不会瞬间向书源并发 10 个请求。

#### C. 向后翻页必须落到上一章章尾

分页模式在章界先显示占位页。此前占位页加载完成后，`currentPageAnchor` 一律按“章内第 0 段”恢复，导致用户从章首向左滑，反而跳到上一章的第一页。

- 新增 `ReaderChapterWindowPolicy.restoreParagraphIndex(chapterIndex:currentChapterIndex:placeholderDirection:)`：向后（章号小于当前章或 `placeholderDirection < 0`）返回 `Int.max`，向前返回 `0`。
- `pageIndex(forChapter:paragraph:)` 已把 `Int.max` 解释为章尾，因此上一章加载完成后精确落在最后一页；章中间的空洞占位页也能按“用户从哪一侧进入”恢复正确端点。
- 预加载标题从“关闭”改为“仅相邻 1 章”，与 `ReaderChapterWindowPolicy.minimumRadius = 1` 的真实行为一致，避免用户误以为完全关闭预取。

#### D. 验证

- 新增 `ReaderChapterWindowPolicyTests.testPlaceholderRestoreUsesTravelDirection`，覆盖向后、向前与中间空洞三种占位方向。
- CI：iOS run `40109182540` / job `120917402615`，commit `7773e2b`，**984 tests / 0 failures / TEST SUCCEEDED**。
- IPA：run `40109182535` / job `120917402989`，`C:\Users\Edc21\Desktop\SourceReadSwift-1.0.29-unsigned.ipa`，11,466,987 字节，SHA256 `C2CC7A38778A76338E6BDA61BC14D0E75BF908A88C7F72485D06368CF6AD8D2A`，Info.plist 1.0.29 / Build 30 / iOS 16.0 / `com.edc21.SourceReadSwift`。
- 四件套：`E:\codex-temp\sourceread\artifacts\reader-continuous-v29\`；回滚在独立副本上执行，10 个修改文件（含本文档）恢复后与 v1.0.28 基线逐字节一致。

**仍待真机验证**：串行预取在弱网下的队列推进速度、向后拖动占位页加载完成后的视觉落点、覆盖/仿真动画与队列回包同时发生时的连续性。本机没有 Xcode/真机，以上只能标记为待验收，不能写成已通过。


---

## 三、 代码路径与核心文件索引 (Where it lives)

| 模块 | 核心源码物理路径 | 作用与责任 |
|---|---|---|
| **排版样式** | `SourceReadSwift/Features/Reader/ReaderImageStyle.swift` | 样式枚举解析、几何尺寸计算、URL 校验 |
| **图片加载** | `SourceReadSwift/Shared/DesignSystem/RemoteImageLoader.swift` | 全局图片内存缓存、并发请求去重、异步解码；识别 `srdata://` 内联图令牌并复用同一缓存 |
| **图片视图** | `SourceReadSwift/Shared/DesignSystem/CachedRemoteImage.swift` | 视图层图片组件，支持请求头透传与尺寸回调 |
| **原生阅读器** | `SourceReadSwift/Features/Reader/NativeReaderTextView.swift` | TextKit 1 排版、NSTextAttachment 内联、异步重排 |
| **翻页阅读器** | `SourceReadSwift/Features/Reader/ReaderView.swift` | 窗口状态、四种阅读表面、跨章页模型、近邻优先串行预取、插图视图与请求头采集 |
| **跨章窗口策略** | `SourceReadSwift/Features/Reader/ReaderChapterWindow.swift` | 双向窗口半径、预取顺序、扁平段落布局、窗口裁剪、页占位与向后落章尾策略 |
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
| **工程配置** | `project.yml` & `SourceReadSwift/App/Info.plist` | 版本声明（1.0.29 / Build 30）；bundle 版本由 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 单一来源派生 |

---

## 四、 验证结果与 CI 证据 (How to verify)

### 1. 自动化测试结果（v1.0.29）
- **GitHub Actions Run ID**：`40109182540`
- **Job ID**：`120917402615`
- **验证 Commit**：`7773e2b`
- **运行结论**：`Success`（`** TEST SUCCEEDED **`）
- **用例总数**：**984 个 XCTest 单元测试全部通过（0 failures, 0 unexpected）**
- **基线对照**：v1.0.28 的 `285950e` 为 983 tests / 0 failures；本轮净增 1 个占位页方向恢复用例
- **本轮新增/关键覆盖**：
  - `ReaderChapterWindowPolicy.restoreParagraphIndex`：向后/向前/中间空洞占位页的端点恢复
  - `ReaderChapterWindowPolicy.prefetchOrder`：最近优先、同距离向后优先，供串行队列直接消费
  - `ReaderChapterPosition.pageOrdinal`：窗口重建后的章内精确页恢复
  - `SearchURLResolverTests.testAppVersionSemantics` 锁定 1.0.29 / Build 30
- **历史**：v1.0.28 为 run `40107402912` / job `120911836046`，983 tests / 0 failures；v1.0.27 为 run `40096362239` / job `120879785198`，969 tests / 0 failures

### 2. IPA 打包产物（v1.0.29）
- **GitHub Actions Run ID**：`40109182535`
- **Job ID**：`120917402989`
- **验证 Commit**：`7773e2b`
- **产物名**：`SourceReadSwift-unsigned-ipa`
- **本地落盘路径**：`C:\Users\Edc21\Desktop\SourceReadSwift-1.0.29-unsigned.ipa`
- **产物大小**：`11,466,987 字节`
- **SHA256**：`C2CC7A38778A76338E6BDA61BC14D0E75BF908A88C7F72485D06368CF6AD8D2A`
- **Info.plist 核验**：`CFBundleShortVersionString=1.0.29`、`CFBundleVersion=30`、`MinimumOSVersion=16.0`、`CFBundleIdentifier=com.edc21.SourceReadSwift`（workflow 内 `PlistBuddy` 断言 + 本地 `plistlib` 复验）
- **历史（v1.0.28）**：`SourceReadSwift-1.0.28-unsigned.ipa`，11,462,716 字节，SHA256 `AA382E773C727F9FD95EDA3FF51AFA6554B85E939780DF6779CE4EDB8BA96402`，run `40107402785`；v1.0.27 为 11,390,330 字节，run `40096362252`

---

## 五、 后续演进建议与未尽事项 (Next Steps for AI)

下一位接手的工程师或 AI 可在此坚实基准上推进以下事项：

0. **阅读器（v1.0.29 已实现双向串行预取，剩余真机验收）**：
   - 四种模式已经共用“当前章 + 前后 N 章”的双向窗口；分页模式用占位页跨边界，滑动模式用扁平段落空间续接。预取已改为近邻优先的串行队列，向后翻页会落到上一章章尾。剩余工作是真机逐项验收手势节奏、覆盖/仿真动画与预取回包同时发生时的视觉连续性。
   - 漫画放大后只能看中心：`ComicPageImageView` 有 1×–3.5× 缩放但没有平移；TabView 内 pan 与翻页手势冲突，需要真机调 `DragGesture` 启用阈值。
   - 跨章窗口目前有边界、预取、锚点和页占位单元测试，但没有真机长文连续滚动/连续翻页回归；长章节回翻和弱网下的占位页仍应作为验收项。
   - 本机没有 Xcode/Swift 工具链，本轮所有 UI 结论来自读码 + 单测 + CI 构建；深色主题对比度、横屏安全区、页脚与悬浮胶囊的重叠仍需真机截图回归。

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
