# SourceReadSwift (纸间) 项目交接与工程全景报告

> **目标受众**：接手本项目的下一位 AI 协作架构师 / 研发工程师  
> **文档基线**：v1.0.21 (Build 22)  
> **更新时间**：2026-10-20  
> **最新 Commit**：`f37a5aa` (状态：全部 GitHub Actions CI 绿灯通过)

---

## 一、 项目全貌与工作区定位 (Project Topology)

### 1. 基础环境与代码库
- **应用名称**：纸间 (SourceReadSwift)
- **Bundle ID**：`com.edc21.SourceReadSwift`
- **本地工作区物理路径**：`D:\Gemini反重力\SourceReadSwift2`
- **主活跃分支**：`codex/swift-v2-lifetime-reader`
- **远程仓库**：`https://github.com/ztcsr5/SourceReadSwift.git`
  - *注：本地 Git remote 已内嵌认证 Token，可直接执行 `git push origin codex/swift-v2-lifetime-reader`。*
- **当前最新交付产物**：
  - 路径：`C:\Users\Edc21\Desktop\SourceReadSwift-1.0.21-unsigned.ipa`
  - 文件大小：`10,906,432 字节 (~10.4 MB)`
  - 验证状态：基于 Commit `f37a5aa`，通过 CI 生成并回传至宿主桌面。

### 2. 技术栈核心选型
- **编程语言**：Swift 5.9+ (全面拥抱 Swift Concurrency: `async/await`, `actor`, `Sendable`)
- **UI 体系**：纯 SwiftUI + iOS 17 HIG 规范，拒绝 UIKit 过度包裹，界面保持纯粹、轻量、高帧率。
- **项目构建工具**：[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`)
  - 严禁直接手动修改 `.xcodeproj` 文件；所有源文件、配置、Bundle Version 均在 `project.yml` 中统一定义，CI 端每次自动执行 `xcodegen generate`。
- **外部依赖（极简纯原生化）**：
  - `SwiftSoup` (HTML 解析与 DOM 抽取)
  - `ZIPFoundation` (EPUB 解压与归档处理)
  - `CryptoSwift` 与 Apple 原生 `CryptoKit` (密码学哈希、MD5、HMAC-SHA256)
  - 系统 `libz` (Zlib 解压缩桥接)
  - 原生 `JavaScriptCore` (Legado 复杂动态 JS 规则沙箱)
  - *架构铁律：严禁引入 RxSwift、Realm、RxCocoa 等过重、过时的三方库，保持零 Pod 纯 SPM 原生化。*

---

## 二、 架构分层与核心代码映射 (Architecture & Code Map)

整个工程按照现代模块化设计进行分层组织：

```
SourceReadSwift/
├── App/                          # 应用入口与生命周期 (SourceReadSwiftApp.swift, Info.plist)
├── Core/
│   ├── Audio/                    # 音频与语音合成
│   │   ├── CloudTTSProtocol.swift       # [新增] 纯 CryptoKit 讯飞/云端 TTS RFC1123 HMAC 签名引擎
│   │   └── LocalTTSPlayer.swift         # iOS AVSpeechSynthesizer 本地朗读实现
│   ├── Compression/              # 解压与二进制格式桥接 (ZlibBridge)
│   ├── Import/                   # 多格式导入与智能转译适配
│   │   ├── HuaHuoBookSourceAdapter.swift    # [新增] 花火阅读书源 JSON 适配器
│   │   ├── HaiKuoShiJieSourceAdapter.swift  # [新增] 海阔视界影视/小说源与 JS 桥接
│   │   ├── SourceImportLinkParser.swift     # 深度链接识别器 (yuedu://, legado://, huahuo://, haikuo://)
│   │   ├── LocalTxtSmartDivider.swift       # [增强] 512KB 滑动窗口流式切分大 TXT
│   │   └── EpubParser.swift                 # EPUB 目录与正文解析
│   ├── JavaScript/               # 动态脚本沙箱
│   │   ├── JSCoreRuntime.swift              # JavaScriptCore 运行环境 (java.* 全套桥接)
│   │   └── LegadoJavaScriptCompatibility.swift # 语法兼容与特征探测
│   ├── Models/                   # 核心不可变数据模型
│   │   ├── Book.swift / Chapter.swift       # 书籍与章节定义
│   │   ├── BookSource.swift / SourceRule.swift # Legado 规则树模型
│   │   └── BuiltinBrowserSourceProvider.swift # [新增] 内置 41KB 官方通用浏览器启发式小说提取源
│   ├── Network/                  # 网络请求与 Session 调度 (LegadoParser, SearchURLResolver)
│   ├── Security/                 # 安全合规风控
│   │   └── B18PlusService.swift             # [新增] 208 个恶意劫持/违规域名与关键词运行时拦截
│   └── Storage/                  # 数据持久化仓库
│       ├── SourceStore.swift                # 书源存储、去重、默认源装载与导入导出
│       └── BookShelfStore.swift             # 书架、本地书籍元数据与阅读进度
├── Features/                     # 业务功能特性模块
│   ├── Bookshelf/                # 书架视图、分组管理与最近阅读
│   ├── Explore/                  # 书源发现、多源聚合搜索
│   ├── Reader/                   # 正文排版、翻页动效、目录树跳转
│   ├── SourceManager/            # 书源管理、编辑、分组校验
│   └── Stats/                    # 阅读统计看板、格式分布与徽章成就
└── Shared/                       # 共享组件与设计系统
    ├── AppVersion.swift          # 全局语义化版本号定义 (v1.0.21, Build 22)
    └── DesignSystem/
        ├── SakuraThemeCatalog.swift         # [新增] 6 款官方 Sakura 响应式排版主题 CSS
        └── AppTheme.swift                   # SwiftUI 原生色彩、字阶与视觉基调
```

---

## 三、 近期重大资产吸收与演进记录 (Reversed Asset Absorption)

在 `v1.0.21` 版本中，我们对官方版「源阅读」iOS 安装包（IPA）进行了底层深度逆向，并将其最精华的核心资产完成纯 Swift 化重构与无损吸收：

### 1. 全网通用小说导航源 (`BuiltinBrowserSourceProvider`)
- **机理剖析**：官方经过多年积累的 `$BROWSER_SOURCE$` 规则库（长达 41KB），支持将任意小说网页 URL（无论 PC 还是移动端）直接填入书架即可解析。
- **包含特性**：包含 100+ 条针对正文、目录、下一页、去防盗、去广告的启发式正则；涵盖拼音首字母过滤、微信号屏蔽、下一页智能拼合等。
- **接入位置**：内置于 `SourceStore.defaultBookSources` 首位。

### 2. 花火阅读 (`HuaHuo`) 与海阔视界 (`HaiKuo`) 双格式适配器
- **花火适配器** (`HuaHuoBookSourceAdapter`)：自动感知 `exploreBookList`, `searchCoverUrl`, `infoTocUrl`, `nextContentUrl` 等字段，转译为 Legado 规范的 `BookSource`。
- **海阔视界适配器** (`HaiKuoShiJieSourceAdapter`)：解析海阔专有的 `find_rule`, `search_rule`，并注入 `window.fy_bridge_app.importRule` 脚本桥接。
- **协议链路**：`SourceImportLinkParser` 扩充对 `huahuo://` 与 `haikuo://` 协议头的支持。

### 3. TXT 大文件流式滑动窗口切分 (`LocalTxtSmartDivider.divideStreaming`)
- **问题背景**：以往解析 30MB+ 的大体积 TXT 时，全量读入内存会导致 iOS 出现 Jetsam 内存溢出崩溃。
- **解决方案**：引入 512KB 分块流式滑动窗口，在章节边界发生跨 chunk 截断时自动保持前驱缓冲区，实现超低内存占用、毫秒级切分 1000+ 章节。

### 4. 208 个 App Store 违规与风控域名过滤 (`B18PlusService`)
- 提取并逆向还原官方封禁的 208 个敏感、恶意跳转域名及色情引流特征词，在网络加载与书源导入前进行拦截，确保应用上架合规性与访问安全。

### 5. 纯原生云端 TTS 协议生成器 (`CloudTTSProtocol`)
- 无需依赖任何旧版 Objective-C SDK 或重型 CocoaPods，采用 Apple 现代 `CryptoKit` 原生生成 RFC1123 标准 GMT 时间戳与 HMAC-SHA256 签名，直接生成科大讯飞等云端 WebSocket 鉴权 URL 及请求载荷。

### 6. Sakura 樱花排版主题资产 (`SakuraThemeCatalog`)
- 提取并内嵌 6 套经商业级验证的阅读器 CSS 主题（经典樱白、极夜幽黑、暗夜暖阳、大地护眼、水墨高对比、深渊纯黑）与 `normalize.css`，支持为后续 WebKit 排版渲染注入专业排版。

---

## 四、 CI/CD 自动化流水线与交付机制 (CI/CD Pipeline)

本项目在 GitHub Actions 上配置了两套全自动构建流，由推送到 `codex/**` 分支自动触发：

### 1. `iOS` 测试流水线 (`.github/workflows/ios.yml`)
- **环境**：`macos-15` (Xcode 最新稳定环境)
- **步骤**：`brew install xcodegen` -> `xcodegen generate` -> 模拟器编译 -> 运行 XCTest。
- **测试现状**：目前全工程包含 **634 个单元测试用例**，最新 commit `f37a5aa` 执行结果为 **100% 通过（0 failure）**。

### 2. `Unsigned IPA` 打包流水线 (`.github/workflows/unsigned-ipa.yml`)
- **目标**：为真机免越狱侧载（TrollStore / 签名证书 / AltStore）生成无签名的 IPA 包。
- **产物构建过程**：
  1. `xcodegen generate` 生成 Xcode 项目。
  2. `xcodebuild -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO` 编译。
  3. `ditto` 工具打包为 `Payload/SourceReadSwift.app` 结构的 `.ipa`。
  4. 上传为 GitHub Artifact `SourceReadSwift-unsigned-ipa`。

### 3. ⚠️ 核心踩坑提醒：GitHub Artifact 下载 403 规避
- **现象**：通过 GitHub REST API 下载 artifact zip 时（`https://api.github.com/repos/.../actions/artifacts/{id}/zip`），GitHub 会返回 `302 Found` 重定向至 Azure Blob Storage（带 SAS 签名）。
- **致命坑点**：如果 HTTP 客户端在重定向请求中依然带上 `Authorization: token ...`，Azure Blob Storage 会判定签名冲突，报错 `HTTP Error 403: Server failed to authenticate the request`。
- **正确做法**：拦截 302 重定向获取 `Location`，随后发起**无 Authorization 标头**的纯 GET 请求下载。本地工具脚本 `scratch/download_latest_ipa.py` 已封装此逻辑。

---

## 五、 关键避坑准则与工程纪律 (Engineering Principles)

后续接手的 AI 必须严格遵守以下准则：

1. **可见性权限铁律 (Access Level Scope)**：
   - 本项目是单个 iOS 应用程序 Target，而非 Framework。大部分核心数据结构（如 `BookSource`, `SourceStore`, `LegadoParser`）作用域均为 `internal`。
   - **绝对禁止**在新增的工具类、服务类或方法上盲目添加 `public` 关键字！一旦方法的参数或返回值使用了 `internal` 类型，Swift 编译器会直接报错：`method cannot be declared public because its result uses an internal type`。统一使用默认的 `internal`。
2. **版本号同步三要素 (Version Bumping Rule)**：
   - 每次升级版本，必须同时修改：
     1. [AppVersion.swift](file:///D:/Gemini%E5%8F%8D%E9%87%8D%E5%8A%9B/SourceReadSwift2/SourceReadSwift/Shared/AppVersion.swift)：修改 `epic`, `major`, `minor`, `build`。
     2. [project.yml](file:///D:/Gemini%E5%8F%8D%E9%87%8D%E5%8A%9B/SourceReadSwift2/project.yml)：修改 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`。
     3. [Info.plist](file:///D:/Gemini%E5%8F%8D%E9%87%8D%E5%8A%9B/SourceReadSwift2/SourceReadSwift/App/Info.plist)：修改 `CFBundleShortVersionString` 与 `CFBundleVersion`。
     4. [SearchURLResolverTests.swift](file:///D:/Gemini%E5%8F%8D%E9%87%8D%E5%8A%9B/SourceReadSwift2/SourceReadSwiftTests/SearchURLResolverTests.swift)：同步更新 `testAppVersionSemantics` 中的数值断言，否则 CI 单元测试会失败。
3. **连续工具调用硬上限 (Circuit Breaker)**：
   - 严格遵守单轮连续工具调用不超过 6~8 步的刹车原则，避免长时间沉没盲跑。遇到长任务应阶段性向用户输出进展。

---

## 六、 后续演进建议与待办清单 (Roadmap & Next Steps)

下一位 AI 可根据用户的进一步指示，优先考虑以下方向：

1. **Sakura 排版主题 UI 接入**：
   - 目前 `SakuraThemeCatalog` 已内置 6 款 CSS，可将其挂接到正文阅读视图 (`ReaderPageView`)，并在阅读设置菜单中增加主题卡片切换。
2. **CloudTTS WebSocket 音频播放器装配**：
   - 目前 `CloudTTSProtocol` 已提供完整的鉴权 URL 和数据帧 payload 生成器。可进一步基于 `URLSessionWebSocketTask` 与 `AVAudioPlayer` 封装流式接收与播放控制器，实现免 SDK 的讯飞云端在线朗读。
3. **书源管理多格式标记**：
   - 在书源列表卡片中，对花火源 (`HuaHuo`) 与海阔视界源 (`HaiKuo`) 增加专属格式角标展示，方便用户识别。

---

*报告生成完毕。项目处于完全健康、全绿灯通过、随时可演进交付状态。*
