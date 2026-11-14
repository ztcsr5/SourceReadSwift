# 纸间夜间改造与接手审计

分支：`codex/perf-120hz-1109`。保护基线：`69729734eb0bae44701632beb55c928fadfe8827`。Antigravity 接手点：`604cfeb73ef1195e5694507cd0ee9d4d6e06bcea`。本轮首个功能候选：`c1ba4b47cf2e19d3699d7b39ddf149d8fa43ba6c`。本文件不是发布凭证；以 GitHub Actions 中同一 SHA 的实际结论和设备实测为准。

## ① Commit 与基线对照

- Antigravity 记录 `70a47fa4-2824-44e4-9778-82d6cef41d6c` 以只读方式复查。末尾 `4720–4722` 为交接/停工状态，不是测试通过凭据。接手时已跟踪工作区与索引干净，远端同为 `604cfeb7`，`69729734` 仍为祖先。
- `69729734..604cfeb7`：15 个提交、147 个文件、`+8606/-1780`。`604cfeb7..c1ba4b47`：22 个文件、`+394/-269`。`69729734..ea557773` 的净差：156 个文件、`+8922/-1886`，不含随后提交的审计、状态与变更日志。文档提交后的精确全量统计和 SHA 用下方命令复核。未跟踪的历史脚本、日志、压缩包未进入提交。

| SHA | 改动 |
|---|---|
| `18bd0fa9` | 核心与氛围主题、深色模式、应用图标、布局选项、自定义主题工坊 |
| `eaf7b40a` | 阅读设置工作台、纸张与壁纸、阅读玻璃、排版扩展 |
| `9f0cca63` | 设置整理、TTS、WebDAV、书签导出、书内搜索、白噪音、AI 提要 |
| `014233fb` | 后台分页、阅读器控制层隔离、共享时钟、调试用性能开关 |
| `605cc164`、`0b87ce55`、`84043c6d`、`a25c9a8b`、`d07e8a5e`、`2f8c0dd6` | 编译修复：导入、滚动、主题枚举、iOS 16 `onChange`、旧 API 别名、剩余工作台错误 |
| `273835db`、`36db1c80` | 单测构造签名调整 |
| `5b4c9d2d`、`a2247cb3` | 阅读设置无障碍标识、图标提示和空白区命中修复 |
| `604cfeb7` | 已挂载宿主的 push 动画判断、WebView 显式会话参数、旧系统测试宿主和取消观测 |
| `c1ba4b47` | 减少读页和设置切换重绘；保留系统侧滑，统一玻璃和壁纸；恢复两个一级设置入口；增加回归 |
| `02e980c383456ced5e62be18bb7c9fbaf4f03e21` | 只保留窗口根部高刷驱动，移除正文和 RSS 内重复挂载 |
| `8e44e5cf9a5d7725bdf8ed7e80d0ec93c04894bd` | 稳定 UIKit 宿主继承实际外观；系统图标确认后才同步内标；一级设置顺序保持 |
| `ea557773cde56a8440f22bd2d8c78ca2c034a63c` | 记录原生交互释放百分比；校正合成短/长拖和离线漫画点击位置；不放宽返回、存档和视口断言 |

```powershell
Set-Location -LiteralPath 'D:\Gemini反重力\SourceReadSwift2'
git log --reverse --oneline 69729734..HEAD
git diff --stat 69729734..HEAD
git diff --name-status 69729734..HEAD
git rev-parse HEAD
git merge-base --is-ancestor 69729734 HEAD
git status --short --branch -uno
```

## ② 逐文件改动明细

以下路径相对仓库根；`SourceReadSwift/` 内文件省略该共同前缀。资源展开见第 ④ 节，精确逐路径增删和行数用第 ① 节命令核对。

### Phase 1：主题、首页与图标

| 文件 | 符号与原因 |
|---|---|
| `Shared/DesignSystem/AppVisualTheme.swift` | `AppVisualTheme`、`migrated(from:)`、`HomeCompositionPreference`、`atmosphericPaperAsset`：核心/氛围名单、旧值回退、独立布局选择与日夜素材。 |
| `Shared/DesignSystem/AppAtelierTheme.swift` | `AppAtelierPalette`：主题色与深色变体。 |
| `Shared/DesignSystem/AppTheme.swift` | `AppTheme` 动态色、`AppPagePaper`、`AppCustomBackdropLayer`：公共纸面、夜色和自定义图。 |
| `Shared/DesignSystem/AppThemeOrnament.swift` | `AppThemeOrnament`：氛围主题装饰，森林绿不增加重边框。 |
| `Shared/DesignSystem/AppThemeSurface.swift`、`BrandGlass.swift` | `AppThemeSurface`、`BrandGlass`：按主题/可访问性解析纸面和玻璃，保留材质路径。 |
| `Shared/DesignSystem/BrandSegmentedControl.swift`、`BookCoverPlaceholder.swift` | 主题令牌、占位外观随新主题兼容。 |
| `Shared/DesignSystem/VideoGlassBackdrop.swift`（删） | 移除两套旧实时视频玻璃主题的背景实现，不等同于移除通用玻璃。 |
| `Shared/DesignSystem/AppCustomThemeStore.swift`、`Features/Settings/CustomThemeWorkshopView.swift`（新增） | `CustomThemePreset`、`AppCustomThemeStore`、`CustomThemeWorkshopView`：多方案、相册/渐变/纯色、独立夜图与取色。 |
| `Shared/DesignSystem/AppIconManager.swift`（新增）、`Features/Settings/AppearanceSettingsView.swift` | `AppIconOption`、`AppIconManager.select`、图标选择器与主题配套提示；仅在系统成功时提交图标，失败时按 UIKit 状态恢复内标，不触发主题全局刷新。选择期间禁用重复点按并反馈。 |
| `Features/Bookshelf/AtelierReadingCard.swift`、`BookshelfView.swift`、`FloatingDeskStyle.swift`、`FloatingReadingDesk.swift`、`ThemedReadingCard.swift` | 阅读卡、书台、书架布局消费 `resolvedHomeComposition` 和新主题令牌；保持现有阅读入口。 |
| `Features/Discover/BookDetailHero.swift`、`Features/Reader/ComicReaderView.swift` | 详情与漫画控件颜色接上主题；未更换详情导航路径。 |
| `Core/Storage/AppBackupPreferences.swift` | `normalized`、`legacyVisualThemeNames`：旧备份主题回退、独立布局/图标和深色配色白名单。 |
| `Features/Reader/Navigation/ReaderNavigationHost.swift`、`ReaderHostingEnvironment.swift`、`ReaderNavigationRouter.swift` | `applyInterfaceStyle` 同步外观到外层 UIKit 宿主、根控制器和窗口；持久根/阅读器不冻结 SwiftUI 色彩方案，继承实时 UIKit 外观；临时内嵌宿主仍接收其局部阅读器色彩。 |

### Phase 2：阅读设置、玻璃、纸张和排版

| 文件 | 符号与原因 |
|---|---|
| `Features/Reader/ReaderSettingsWorkbench.swift` | `ReaderSettingsWorkbench`、`ReaderWorkbenchContext`：紧凑主卡、背景滑条、翻页和功能格；接手将路线收成一个 `Screen`，只转场面板内容，裁切底缘，移除全屏级形变与壁纸叠图。 |
| `Features/Reader/ReaderChromeSurface.swift` | `ReaderChromeSurface`、`ReaderControlPressStyle`：顶栏、底栏、设置共用未染白的 `.regular`／`.ultraThinMaterial`；按下即反馈，松手回弹，遵循减少动态效果。 |
| `Features/Reader/ReaderChromeLayers.swift` | `ReaderScrollChromeLayer`、`ReaderSettingsDrawerLayer`：菜单显示时不再把不透明正文页眉叠在顶部玻璃下；保留静态正文页眉和状态栏保护；移除随路由传播的多余 spring。 |
| `Features/Reader/ReaderView.swift` | `pageBackground`、`readerBackdrop`、`readerOverlay`、`atelierPanel`、`readerValueSlider`：滚动/分页共用日夜壁纸、菜单和面板墨色/强调色接线，移除进度条填块和底栏额外大阴影。原调字号、装帧、扉页、点击区、滚屏、换源入口仍在。 |
| `Features/Reader/ReaderWallpaperAdjustment.swift`、`ReaderCustomWallpaperStore.swift`、`ReaderWallpaperEditorView.swift`、`ReaderWallpaperView.swift` | `ReaderWallpaperAdjustment`、`saveEditedWallpaper`、`ReaderWallpaperUIImageView.configure`：旧壁纸继续读，保存夜间压暗和配色；接手删除编辑预览与分页的第二层硬罩，异步生成预渲染模糊和纹理，输入不变不重复布局。 |
| `Features/Reader/ReaderSettingsModels.swift`、`ReaderAtelierPreview.swift`、`ReaderFontScheme.swift`、`ReaderBindingPreferences.swift` | `ReaderBackground`、`ReaderTextAlignment`、字体家族/字重、`ReaderAtelierPreview` 和装帧键；接手分离壁纸日间浅字偏好与夜间纸张状态。 |
| `Features/Reader/ReaderPageGeometry.swift`、`ReaderPageLayoutEngine.swift`、`ReaderPageTextView.swift`、`ReaderChapterPaginator.swift`、`ReaderTextPagePaginator.swift` | 分页几何、对齐及字重上下文、标题/正文墨色、排版入参。 |
| `Features/Reader/WebReaderDocument.swift`、`WebScrollReaderView.swift`、`NativeReaderTextView.swift` | WebKit CSS 字号/字重/对齐和原生选区/朗读范围；保留 WebView 优先级与传入会话。 |
| `Features/Reader/ReaderPaperTexture.swift`、`ReaderIllustratedBackground.swift` | 纸纹和全尺寸插画后台预处理；接手设置横向列表惰性加载，使用独立小图缓存。 |
| `Features/Reader/ReaderAutomationPolicy.swift`、`Features/Settings/ReaderSettingsPage.swift` | 面板尺寸和阅读偏好入口，替换旧双轨设置。 |

### Phase 3：一级设置、朗读和阅读工具

| 文件 | 符号与原因 |
|---|---|
| `Features/Settings/SettingsView.swift`、`Features/Discover/DiscoverView.swift` | `AdvancedSettingsView` 与一级信息架构、寻书筛选及剪贴板检查；接手把 `AIChatView` 和 `SourceWritingView` 两条原路由移出高级设置。 |
| `Features/Settings/AIChatView.swift`、`Features/Reader/ReaderView.swift` | `AIChatRecapSeed`、`openAISpoilerFreeRecap`、`collectReadableChapterSources`：准备当前章及之前的缓存片段给 AI 提要；严格段落截断仍列风险。 |
| `Core/Audio/HttpTTSVoiceStore.swift`（新增）、`Features/Settings/TTSSettingsView.swift`、`Features/Reader/ReaderView.swift` | `HttpTTSVoiceStore`、`ReaderVolumeKeyListener`、`ReaderAmbientSoundscapeEngine`、`ReaderSpeechController`：管理 HTTP 音源、音量键策略、氛围音、下段预缓存和锁屏控制。第三方服务和真机硬件未逐项验证。 |
| `Core/Network/WebDAVAutoSyncCoordinator.swift`（新增）、`Features/Settings/WebDAVSyncView.swift`、`App/SourceReadSwiftApp.swift`、`App/RootTabView.swift` | `performAutoUploadIfNeeded`、`checkForNewerRemoteBackupIfNeeded`、`RootCoordinatorAlertsOverlay`：退后台备份、提示并恢复更新的远端备份。单纯退出阅读器没有上传调用；当前也不是只跳到远端进度。 |
| `Features/Reader/BookmarkExporter.swift`（新增）、`Features/Settings/ReaderDataManagementViews.swift`、`Features/Reader/ReaderView.swift` | `BookmarkExporter`、`ReaderInBookSearchEngine`、`runInBookSearch`：导出 Markdown/纯文本、搜索正文并跳段。网络书只检索窗口和缓存，并非搜索未下载正文。 |

### Phase 4：切换成本、分页和导航边界

| 文件 | 符号与原因 |
|---|---|
| `Features/Reader/ReaderAsyncPaginationCoordinator.swift`、`ReaderSharedClock.swift`（新增） | `ReaderOffMainActorPaginator`、`ReaderChromeCoordinator`、`ReaderSharedClock`：后台 TextKit、控制层单独订阅、分钟级共用时钟。 |
| `Features/Reader/CoverPageReaderView.swift`、`PageCurlReaderView.swift`、`ReaderView.swift` | 复用页面载体、固定页面几何、`rebuildPagedBlocksCacheAsync`；短章节冷开及部分 fallback 仍可同步运行，不称为完全异步。 |
| `Core/Storage/ChapterContentCacheStore.swift`、`CustomFontManager.swift`、`FontImportPolicy.swift` | 缓存字节增量统计、字体异步登记及兼容读取。 |
| `Shared/Performance/ReaderPerformancePolicy.swift` | 分页调度与帧率策略常量；`PerformanceMode` 保持调试开关、默认关闭。 |
| `App/RootTabView.swift` | 接手时移除 tab shell 对整个 `AppState` 的 `@EnvironmentObject` 订阅，仅监听 `isTabChromeHidden` 的变化；子页面和 TabView 状态不换宿主。 |
| `Features/Reader/ReaderView.swift`、`Features/RSS/RSSArticleReaderView.swift`、`scripts/test_perf_minimal_scope.py` | 每个窗口保留一个根部 `highRefreshRateSurface()`；删正文和 RSS 内各自的显示链路挂载，保留根部请求。源码回归先检出两个重复入口，再通过；真机收益未量化。 |
| `Features/Reader/Navigation/ReaderNavigationRouter.swift`、`ReaderNavigationHost.swift`、`Features/Bookshelf/ReaderBookPassageController.swift` | 保留 UIKit 自带 edge/animator。手势跟手期间不提前发布 `.returning`；真正退出才提交会话。`onInteractivePopEnd` 记录 UIKit 取消/完成。保留旧系统未挂载 push 保护及显式 `nativeSession` 传递。 |

### 回归、脚本与构建配置

- `SourceReadSwiftTests/AppLayoutDensityTests.swift`、`ReaderNativeNavigationTests.swift`、`TabChromeRegressionTests.swift`：实际根宿主注入、上屏/停放与同一 tab 控制器。`ReaderCompatibilityNavigationTests.swift`：旧系统以 UIKit 栈、变换和位置状态核验取消与完成，不依赖只在新系统有的回调次数。
- `SourceReadSwiftTests/ReaderControlsMaterialTests.swift`、`Release116VisualTests.swift`、`Release117WallpaperEditorTests.swift`：系统材质可用性/不透明调试开关、窄/深色快照、缩略图缓存与日夜遮罩实测。
- `SourceReadSwiftTests/AIChatTests.swift`、`CloudTTSCompletionTests.swift`、`WebDAVSyncServiceTests.swift`：AI、朗读完成和备份 API/行为兼容；不代表连通所有第三方服务。
- `SourceReadSwiftTests/AtelierLayoutTests.swift`、`AtelierThemeTests.swift`、`FloatingReadingDeskTests.swift`、`ForestBrandThemeTests.swift`、`HomeLayoutEvidenceTests.swift`、`Release117AppearanceTests.swift`、`Release117MotionSystemTests.swift`、`Release117PolishTests.swift`、`Release117ThemeCollaborationTests.swift`、`RootTabGlassTests.swift`、`VideoGlassThemeTests.swift`：新主题名单、结构、材质和暗色视觉；旧视频测试文件留作删除项兼容验证。
- `SourceReadSwiftTests/ReaderBackgroundPickerTests.swift`、`ReaderPageHostingTests.swift`、`ReaderPerformancePolicyTests.swift`、`ReaderSettingsPageTests.swift`、`Release117ReaderPersonalizationTests.swift`、`SakuraReaderPaletteTests.swift`、`Stage33ReaderExperienceTests.swift`、`WebReaderDocumentTests.swift`：新阅读背景可选项、分页、布局参数、旧阅读纸张、WebKit CSS 与页面体验。
- `SourceReadSwiftUITests/AtelierHomeUITests.swift`、`ComicReaderFlowUITests.swift`、`FloatingReadingDeskUITests.swift`、`RootTabGlassUITests.swift`：实际首页/主题/漫画/底栏路径；接手为两项侧滑补失败图、保持相同交互期限和原会话断言，并加一级 AI 与 Web 写源真实点开测试。
- `ReaderNavigationSessionTests.swift`、`VideoGlassThemeTests.swift`：外观快照可随 UIKit 实时更新；系统图标失败不改内标，重置主图标清除 UIKit 备选名。漫画 UI 先让行中心脱离导航栏，再验证离线库标题与第二章、真实解码和页内恢复，未改应用缓存逻辑。
- `scripts/test_atelier_redesign.py`、`test_home_presentation.py`、`test_product_quality_scope.py`、`test_reader_fallback_boundary.py`：更新源码守卫；原生/旧版 tab 数量和禁止重建守卫保留，增加 tab shell 不订阅全量 AppState 的检查。
- `.github/workflows/ios.yml`：旧系统取消/完成预算、让 iOS 16.4/17.5 各自报告（不因 iOS 26 红灯跳过）、增加 iOS 26 的默认速度短拖和一级设置测试。保留原单测、UI、完整构建；`unsigned-ipa.yml` 不改。

## ③ 删除项与旧数据兼容

- 原 App 主题移出枚举：`botanical`、`editorial`、`coast`、`rose`、`graphite`、`folio`、`blueprint`、`berryLake`、`blushInk`、`periwinkleCocoa`、`peachMoss`、`inkViolet`、`pineMist`、`videoAurora`、`videoEmber`。`AppVisualTheme.migrated`/`bootstrapSelection` 及 `AppBackupPreferences.normalized` 将已知历史值回退为 `.classic`。默认全新安装仍是 `.forest`，既有白名单选择不改。降级不是逐主题一一复原；如果旧值已被写成 `.classic`，revert 不会重建用户原选项。
- `VideoGlassBackdrop.swift` 是 `69729734..c1ba4b47` 唯一整个删除文件。没有删除测试文件；具体替换看 `git diff 69729734..HEAD -- SourceReadSwiftTests SourceReadSwiftUITests scripts`。
- 阅读纸张只精简 `ReaderBackground.pickerCases`，保留旧枚举 rawValue（如 `kraft`、`lavender`、`azure`、`gray`、Sakura 色板）。`ReaderWallpaperAdjustment.init(from:)` 为新增字段提供缺省值，`ReaderWallpaperRepository.load()` 仍可读旧 `custom_reader_wallpaper.jpg`；接手不迁移用户壁纸或阅读记录。

## ④ 新增资源与工程配置

- `SourceReadSwift/App/Assets.xcassets` 新增 23 个资源集（46 个 Git 文件，每套图 + `Contents.json`）：
  - `AppIcon{Classic,Klein,Shuimo,Wuxia,Anime,Kawaii,Noir}.appiconset`，各有 `AppIcon-1024.png`。
  - `BrandMark{Classic,Klein,Shuimo,Wuxia,Anime,Kawaii,Noir}.imageset`，现有主 `BrandMark` 作为第 8 种内标。
  - `Theme{Shuimo,Wuxia,Anime,Kawaii}{Day,Night}.imageset` 及 `ReadingStarlight.imageset`。原 `ReadingBamboo`、`ReadingGinkgo`、`ReadingMountains`、`ReadingTide` 和三个随包字体未移除。
- `project.yml` 新设 `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS: YES`，`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` 指定七套；无手写 `CFBundleAlternateIcons`。`604cfeb7` 的实际 IPA（产物 `14103509911`，外层 ZIP 33,466,567 字节、SHA-256 `43e793d2f100c14121caf4081ced45700cbc9fc65bfd23671d76e5c930583042`）内 `CFBundleIcons` 已生成七项，主项 `AppIcon`，含 `Assets.car`（14,255,352 字节）。检查到编译声明与资源目录，不能替代 `setAlternateIconName` 的真机成功回调。
- `c1ba4b47` 的实际 IPA（产物 `14108455027`，外层 ZIP 33,561,944 字节、SHA-256 `8601873d3554de9891b905afacc822fa9f21b4d5417ff57c408eff8c2f768739`）也包含七项备选和 `Assets.car`；此 IPA 对应的 iOS 回归未全绿，不作为正式包。
- 本轮未重新生成四套主题艺术，也没有删改素材。阅读色卡由随包图在后台准备最长边 384 px 的小图，放独立内存缓存；装饰全尺寸图仍走原异步内存缓存；相册阅读壁纸的降采样文件写入路径不变。不要把随包插画缓存或模糊变体描述成已全部落盘。

## ⑤ 红线逐项自证

| 规则 | 证据与边界 |
|---|---|
| 系统边缘侧滑 | `ReaderNavigationRouter` 仍使用 `interactivePopGestureRecognizer`；手势 pop 的自定义 animator 为 `nil`；内容 pan 不变；Zoom 仍只由显式隔离启动参数开启。`c1ba4b47` 未改正文边缘门禁、`BookDetailView` 路由、书架入口、读前介绍页、会话保存/停放判断。 |
| 森林绿纯白 | 本轮不改 `.forest`、`AppTheme` 或资源。已看 `604cfeb7` 森林绿浅色组件与真实首页证据；保留 `ForestBrandThemeTests`，不以灰底替代玻璃。 |
| 通透玻璃 | 顶、底、设置三者统一 `.glassEffect(.regular)`，iOS 16–18 使用 `.ultraThinMaterial`；系统减透明、增强对比、手选纸面、开发者性能开关才走原有不透明分支。底栏没有额外大阴影或包住滑轨的填块；正文滚动固定页眉的遮字保护仍保留。 |
| 主线程 | 本轮消除设置路由对整个滚动视图的几何缩放、tab shell 全量订阅、色卡原图同步展示和自定义壁纸 `configure` 同步高斯模糊。未声明全 App 120 Hz、彻底解决 543 ms 或证明 GPU 已不掉帧。 |
| 保留能力 | 不重做 `ReaderChapterWindow`、`ReaderTapAction`、自动阅读、换源、书签/金句卡，保留现有代码路径。未动生产签名、更新渠道、用户配置文件。 |

## ⑥ 客观验证与待人工复审

| SHA | 工作流 | 实测状态 |
|---|---|---|
| `a2247cb3` | [iOS 43558160275](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43558160275) | `build`、`native-tabs` 通过；16.4/17.5 失败：兼容动画 `didShow` 假设、未挂载宿主进入 WebView 等待超时。 |
| `604cfeb7` | [iOS 43570143117](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43570143117) | `build` 单测 2,001、0 失败、2 跳过；UI 46 项、1 失败（`:689`，`reader-startup.log` 对同一进程实际记录 `BEGIN interactive=1`、`END cancelled=0`，短拖被 UIKit 判为完成，不是页面等待）。`native-tabs` 步骤 13 快速侧滑失败（`:621`，UIKit 已启动，超时仍是 reader top，`interactivePops=1`；WebKit `dx=115` 是页内坐标，不等于手指位移）；旧系统被前置失败跳过。 |
| `604cfeb7` | [IPA 43570143098](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43570143098) | `package: success`。这是用户手里的旧包，不是新修复通过。 |
| `c1ba4b47` | [iOS 43578980735](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43578980735)、[IPA 43578964075](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43578964075) | 设备 Release 成功。iOS 18：2,003 单测、0 失败、2 跳过；47 UI、1 失败（短拖）。iOS 26：718 定向单测全过，短拖和离线漫画 UI 各失败一项；设置 8/8 和 20 次进出测试通过。iOS 17.5：10 单测、4 UI 全过；iOS 16.4：10 单测全过、4 UI 中仅快拖失败（UIKit `native-pop:cancelled`）。 |
| `9679e801`（隔离快照） | [iOS 16.4/26 侧滑诊断 43581060313](https://github.com/ztcsr5/SourceReadSwift/actions/runs/43581060313) | 两系统快拖通过；iOS 16.4 4/4 UI，1 个真实根单测的两条断言失败（WebContent 启动 106.65 秒，正文光标未上屏）；iOS 26 6 项侧滑 UI 中仅 20% 默认速度短拖失败。快拖的首次成功、5 秒和同会话断言保留。 |
| 当前文档提交的 `HEAD` | [iOS 工作流](https://github.com/ztcsr5/SourceReadSwift/actions/workflows/ios.yml)、[IPA 工作流](https://github.com/ztcsr5/SourceReadSwift/actions/workflows/unsigned-ipa.yml) | 推送后按 `head_sha` 确认两个工作流；提交时未运行，不能借用上表的候选状态。本文件无法在生成提交哈希及其 Run ID 之前嵌入两者；以下命令列出实际运行编号和结果。 |

```powershell
$sha = git rev-parse HEAD
gh run list --commit $sha --limit 10 --json name,headSha,status,conclusion,databaseId,url
```

本地（Windows）：`python -B -X utf8 -m unittest discover -s scripts -p "test_*.py" -q` 188 项通过；`python -B -X utf8 scripts/audit_swift_name_shadowing.py` 0 项；`python -B -X utf8 scripts/audit_current_swift_syntax.py 69729734` 检查 102 个 Swift 文件、无新增解析错误，生成报告未提交；`git diff --check` 通过。任务书点名的 `scripts/check_swift_balance.py` 不存在；本地语法审计不替代 Xcode typecheck。

`c1ba4b47` 的离线漫画失败层级 `comic-offline-26-a11y-14109618082.txt`：`设置` 导航栏覆盖 y=59–113，`settings.offlineComics` 行中心 y=78.7；所谓的点击后依然是设置页。此证据不是离线图片被清空。短拖失败的原生日志有 `BEGIN interactive=1` / `END cancelled=0`，也不是正文拦截了边缘手势。

基线快照：iOS 26 `14105752090` 和 macOS-15/iOS 18 `14105818093`，按 ZIP 范围下载原始 PNG，证据目录 `F:/SourceReadSwift/overnight-20261114/verification` 内有 `SELECTED.json`、各图 SHA-256 和模型预览（≤1 MiB）。目测 iOS 26：同页底栏更厚且有附加填块，设置排版子页内容越出圆角底边，森林绿浅色白底。主题组件快照不使用实际 `AppPagePaper`，不能证明氛围底图在各屏渲染；真实首页证据另作对照。`604cfeb7` 相邻提交差异没有证明 `hostReady` 或显式 `nativeSession` 导致两种手势结果，不能据此盲目还原。

`theme-14105818093` 中实际浅色首页可见：水墨丹青与江湖武侠都有纸面/边缘墨画，但标题与主阅读卡未形成统一的视觉语言；二次元和可爱风虽然壁纸不同，卡片结构、留白与粉色控件高度近似。建议保留森林绿作稳定对照，以水墨丹青实际首页做一套新样板定方向，先确认主卡、标题和点缀的关系再扩到其余主题；不按四套一起重画，也不以旧的组件色板截图冒充新的主题完成。

**真机复验优先顺序**（旧包和新包使用同一 ProMotion 手机、同一本本地书、同一主题/电量状态、性能优先关闭；每条冷/热分别重复）：

1. `主页 → 寻书 → 设置 → 主页`、书架 → 详情 → 侧滑回主页；观察点按反馈、标题同步、落地第一下点击和首页卡片不挪动。
2. 正文快甩、慢拖后取消、取消后再返回、首次点继续阅读保留同一段；正文中部翻页、选字、开目录时手势不能误退出。
3. 顶/底栏和 P3 设置对照：纯白、黑纸、相册壁纸和不同对比度。快速点入排版/配色/更多并返回，看按下、切换、底缘不露字、读位不变。
4. App 内图标和桌面实际切换，失败不错误改内标；四种核心和四种氛围主题使用真实首页的日/夜对照。不满意的主题先定参考方向，再独立改视觉，不在性能对照里换主题。
5. 设置 → 高级设置 → 开发者调试 → 全局帧率采样，按相同脚本各采 30 秒。记录交互段的 P95/P99、最慢回调、调度缺口、低电量/温度。该采样只代表主线程回调；实际呈现掉帧用 [Apple Animation Hitches / SwiftUI Instruments](https://developer.apple.com/documentation/xcode/improving-app-responsiveness) 在同一手机对照。没有原始同场景 trace，不把历史 543 ms / 24 ms 数字当作本轮量化基线。

**仍须复审**：`ReaderView.rebuildPagedBlocksCache` 同步短章与紧急回退；`RootTabView` 外层观察链和 `ReaderHostingEnvironment` 深色覆盖；`AppRefreshRateKeeper` 真机才有常驻显示链路，模拟器不能证明其成本；`ReaderWallpaperEditorView` 阅读壁纸只有一张图 + 日夜压暗（全局主题工坊才有两张图），取色和最终前景对比度待设备抽样；`openAISpoilerFreeRecap` 有当前章全文/兜底与不剧透风险；WebDAV 只接了后台，没有独立退出阅读时的静默进度上报。未逐家验证 HTTP TTS 兼容、远端 WebDAV 恢复或音量键真机行为。

**回滚本轮功能候选**：先用 `git log --oneline 604cfeb7..HEAD` 核对范围，再将本轮提交按新到旧 `git revert`，保留 `604cfeb7` 和 `69729734`。只回退高刷去重可单独 `git revert 02e980c3`。
