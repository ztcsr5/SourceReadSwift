# SourceReadSwift (纸间) 项目交接全量备忘录

> **交接目标**：交接给下一位 AI 协作者 / 研发工程师  
> **文档基线**：v1.0.22 (Build 23)  
> **交接时间**：2026-10-21  
> **验证 Commit**：`4195a5b`（状态：全部 GitHub Actions CI 单元测试与打包通过）  
> **最新产物**：`C:\Users\Edc21\Desktop\SourceReadSwift-1.0.22-unsigned.ipa`（11,266,839 字节）

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
  - 路径：`C:\Users\Edc21\Desktop\SourceReadSwift-1.0.22-unsigned.ipa`
  - 大小：`11,266,839 字节 (~10.7 MB)`
  - 验证状态：基于 Commit `4195a5b`，通过 GitHub Actions CI 真实打包下载。

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

## 二、 v1.0.22 核心功能链实现 (What Changed)

在 `v1.0.22` 版本中，我们彻底打通了书籍插图与漫画排版的完整生命周期闭环：

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

### 1. 排版策略与尺寸规范 (`ReaderImageStyle.swift`)
- 定义 `ReaderImageStyle` 枚举：`standard` ("DEFAULT")、`full` ("FULL")、`text` ("TEXT")、`single` ("SINGLE")。
- 提供 `ReaderImageSizingPolicy.size(for:style:containerWidth:maximumHeight:)`，精确计算插图在不同设备与排版样式下的显示尺寸。
- 提供 `ReaderImageSizingPolicy.imageURL(in:)`，要求必须具备合法 URI 协议（`scheme != nil`），严防普通文本误识别。

### 2. 线程安全图文加载器 (`RemoteImageLoader.swift`)
- 替代原有私有 `ImageMemoryCache`，实现全局共享的 `@unchecked Sendable` 内存图片缓存与任务去重器。
- 支持同步读取 `cachedImage(for:)`，在首次 TextKit 渲染命中缓存时直接生成真实图文附件。
- 支持带 Headers 的异步下载 `image(for:headers:)`，合并多处重复请求任务，避免同一张插图并发重复请求。

### 3. 原生 TextKit 1 滚动排版 (`NativeReaderTextView.swift`)
- `Configuration` 与 `TextLayoutSignature` 扩展支持 `imageStyle`、`imageHeaders` 与 `imageColumnWidth`。
- `ReaderNativeTextLayout` 实现 `replacingImageParagraphs`：
  - 遇到 `[img]url[/img]` 段落时，将其替换为包含 `NSTextAttachment` 的单字符（`\u{FFFC}`）属性字符串。
  - 使用逆序遍历更新后续段落 ranges 的 location 偏移，确保段落级语音高亮（TTS）与行数映射不受破坏。
  - 图片未缓存时绘制轻量优雅的圆角卡片与相框占位图；图片加载完成后自动通知 Coordinator 重新计算并保持视口偏移平稳。

### 4. 翻页模式全宽渲染 (`ReaderView.swift`)
- 提取专门的 `ReaderIllustrationView` 组件，根据 `currentImageStyle.stretchesToColumnWidth` 自动切换全宽或限高渲染。
- 在 `scrollReaderContent` 中向 `NativeReaderTextView` 传入实时的 `imageStyle`、`imageHeaders` 与列宽。

### 5. 防盗链请求头透传 (`SourceRequestBuilder.swift`)
- 新增 `imageRequestHeaders(for source: BookSource) -> [String: String]`。
- 自动提取书源配置的 User-Agent、Cookie 与自定义 header，并补充符合源域名的 `Referer` 与标准图片 `Accept`，确保 CDN 图片不被防盗链拦截。

### 6. 多页章节续接保活 (`SourceEngine.swift`)
- 章节分页合并时，在最终的 `ChapterContent` 初始化中传递 `imageStyle: firstPage.imageStyle`，避免后续分页丢失排版指令。

---

## 三、 代码路径与核心文件索引 (Where it lives)

| 模块 | 核心源码物理路径 | 作用与责任 |
|---|---|---|
| **排版样式** | `SourceReadSwift/Features/Reader/ReaderImageStyle.swift` | 样式枚举解析、几何尺寸计算、URL 校验 |
| **图片加载** | `SourceReadSwift/Shared/DesignSystem/RemoteImageLoader.swift` | 全局图片内存缓存、并发请求去重、异步解码 |
| **图片视图** | `SourceReadSwift/Shared/DesignSystem/CachedRemoteImage.swift` | 视图层图片组件，支持请求头透传与尺寸回调 |
| **原生阅读器** | `SourceReadSwift/Features/Reader/NativeReaderTextView.swift` | TextKit 1 排版、NSTextAttachment 内联、异步重排 |
| **翻页阅读器** | `SourceReadSwift/Features/Reader/ReaderView.swift` | 阅读器页面组装、插图视图、请求头采集 |
| **请求构建器** | `SourceReadSwift/Core/Network/SourceRequestBuilder.swift` | 图片防盗链 Header 构建（Referer / UA） |
| **正文解析器** | `SourceReadSwift/Core/Rules/ContentParser.swift` | 从 HTML / JSON 规则中提取 `imageStyle` |
| **正文模型** | `SourceReadSwift/Core/Models/BookModels.swift` | `ChapterContent.imageStyle` 模型与向下兼容构造器 |
| **缓存持久化** | `SourceReadSwift/Core/Storage/ChapterContentCacheStore.swift` | 章节正文磁盘/内存缓存条目扩展 |
| **单元测试** | `SourceReadSwiftTests/ReaderImageStyleTests.swift` | 样式解析、几何计算、图文附件与请求头全量测试 |
| **文档基线** | `docs/JSON-IOS-COMPATIBILITY.md` & `docs/SOURCE-CAPABILITY-MATRIX.md` | 能力矩阵与 iOS 兼容边界同步更新 |
| **工程配置** | `project.yml` & `SourceReadSwift/App/Info.plist` | 版本升级声明（1.0.22 / Build 23） |

---

## 四、 验证结果与 CI 证据 (How to verify)

### 1. 自动化测试结果
- **GitHub Actions Run ID**：`39560398380`
- **运行结论**：`Success`
- **用例总数**：**640+ 个 XCTest 单元测试全部通过（0 failure, 0 error）**
- **关键测试覆盖**：
  - `ReaderImageStyleTests.testReaderImageStyleParsing`
  - `ReaderImageStyleTests.testReaderImageStyleProperties`
  - `ReaderImageStyleTests.testImageURLParsing`
  - `ReaderImageStyleTests.testSizingPolicyFullStyleExpandsToColumnWidth`
  - `ReaderImageStyleTests.testSizingPolicyDefaultStylePreservesSmallerImage`
  - `ReaderImageStyleTests.testSizingPolicyDefaultStyleShrinksOversizedImage`
  - `ReaderImageStyleTests.testSizingPolicyEnforcesMaximumHeight`
  - `ReaderImageStyleTests.testRemoteImageLoaderInsertAndLookup`
  - `ReaderImageStyleTests.testNativeTextLayoutReplacesImageParagraphWithAttachment`
  - `ReaderImageStyleTests.testSourceRequestBuilderProvidesImageHeaders`
  - `ContentParserTests.testHTMLContentPropagatesImageStyle`
  - `ContentParserTests.testJSONContentPropagatesImageStyle`
  - `ChapterListMetadataTests.testReverseTocFlagReversesCollectedChapterList`

### 2. IPA 打包产物
- **GitHub Actions Run ID**：`39560398449`
- **打包产物**：`SourceReadSwift-unsigned-ipa`
- **本地落盘路径**：`C:\Users\Edc21\Desktop\SourceReadSwift-1.0.22-unsigned.ipa`
- **产物大小**：`11,266,839 字节`

---

## 五、 后续演进建议与未尽事项 (Next Steps for AI)

下一位接手的工程师或 AI 可在此坚实基准上推进以下事项：
1. **`payAction` 付费动作执行**：
   - 目前产品边界为“展示 VIP 标记，不伪造解锁”。
   - 可在阅读器内遇到 VIP 章节时，提供“购买本章”按钮，调用源内声明的 `ruleContent.payAction`（通常为跳转购买链接或执行特定 JS）。
2. **`imageDecode` 字节级拼图解码**：
   - 当前版本已完整支持 URL-rewrite 级别的 `imageDecode`。
   - 对极少数将图片进行反爬切片拼接（JS 返回 `byte[]` 或 Base64 拼图矩阵）的特殊漫画源，可构建底层 CoreGraphics Canvas 拼图管线。
3. **目录逐章字数展示 (`wordCount`)**：
   - `ChapterListParser` 已解析目录 `wordCount`，可在目录抽屉视图的章节副标题中渲染展示。
