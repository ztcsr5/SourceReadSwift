# 1.1.7 · 动效系统与阅读个性化 · 2026-11-02

## 范围与基线
- 用户暂停启动引导实验；不再修改实验 App。正式版已验证基线 89c9a51/build 128；当前从保留该基线与实验历史的分支继续，不 reset/stash/clean。
- 新分支 codex/reader-motion-117；保留用户 RECOVERY、本地未跟踪文件与实验 STATUS 修改。
- 第 3 点按单本最新阅读，不做多本轮播。P1 用于大封面、取色、单本信息的构图，不复制播客时长。第 10 点用户明确只指章节名。
- 不新增依赖；使用现有 SwiftUI/UIKit、封面缓存与降采样、CoreText、原生导航。网关/模型验收仍由用户手测，不发请求。

## 决定性红灯证据
- 先提交 3241712 的原生回归，不先改实现：iOS run 41418642242/build job 125188554172 失败。
- ReaderRecovery119Tests.swift:376：拖动 -4 pt 时，承载层 center 从 (195,422) 变为 (191,422)；第 377 行 transform.tx 仍为 0，而期望 -4。
- 源码每帧先将五个 hosting view.frame 重设为容器，再移动三个 frame.origin，改变布局几何。4a0060d 仅改这一变量：安装/窗口尺寸变化时定几何，拖动只更新 transform；原有提交/取消/排队/拆卸断言不放宽。
- 原始日志保留 F:/SourceReadSwift/reader-motion-117/red/。这是布局热路径回归，不是 FPS 测量，也不能排除真机其他瓶颈。

## 实现与验收矩阵
| 项目 | 当前源码 | 验收边界 |
|---|---|---|
| 1 封面取色 | 保留旧低饱和取色契约，增加鲜明色分量；24 px 离屏取样、缓存复用，无第二次下载 | 待本 HEAD 原生测试/截图 |
| 2 滑动顿挫 | 合成位移替代每帧 hosting 几何重设 | 红灯已复现，修后原生与真机待验收 |
| 3 正在阅读 | 只展示 recentBooks.first，大封面/景深/取色底/真实继续阅读/独立更多菜单 | 待 P1 构图截图与真机体验 |
| 4 Hero | iOS 18+ 系统 zoom，书架封面→详情、详情封面→阅读；16–17 保留系统 push | 系统时长由 OS 管理，不伪称可精确设为 440 ms；交互式返回/取消待验收 |
| 5 统一动效 | AppMotion 统一按压、导航、展开、背景、书笺参数；系统减少动态 + App 开关；核心书架/详情/导航/阅读菜单接入 | 不是全 App 每个旧动画已迁移；书笺保存反馈尚未接通 |
| 6 详情空间 | 大封面取色头部，滚离后简洁标题栏；目录/书源/阅读逻辑保留 | 待原生截图与实际滚动 |
| 7 壁纸顶部 | 固定页眉使用同视口壁纸裁切而非白色纸块；系统状态栏可见时默认不重复顶部时间电量，可独立开启重复 | 需原生组件截图与真机完整壁纸验收 |
| 8 导入字体 | 放开文件提供方类型筛选，实际校验后缀/64 MB/字体描述；支持字体集合；坏文件不覆盖旧字体 | 提供方误标类型是待真机验证的假设；不宣称已复现用户网盘 |
| 9 页眉 | 独立字号/顶部间距/浓度，分页和滚动使用相同有界参数与保护高度 | 待边界/位置回归 |
| 10 章节名 | 独立字体/字号/加粗/标题间距；分页测量与绘制、Web 标题保持一致 | 不改变正文字号；重排沿用锚点机制，待回归 |
| 11 新主题 | 新增藏书票馆、水墨留白、蓝图书库；切口/齿线/山形/网格/边框/字形有区别，保留旧六主题 ID | 新色对比本地计算均 ≥ 6.47:1；待实际主题截图，不只验枚举 |

## 后续交付门槛
- 新源码必须在同一 HEAD 跑完整原生回归与 iOS 26 定向回归；本地语法检查不能代替 Apple SDK。
- Hero 返回取消、连续滑动、壁纸全屏、字体文件提供方属于实际交互验收；60/120 FPS 必须测量，不把刷新率配置当成实测。
- 暂不把未接通的“保存选中文字→票根→书笺收藏”宣称完成；沿用既有书签/金句功能，下一阶段打通真实选区和保存结果后再加生成动画。
- 回滚只 revert 本分支本轮提交，不回退用户原有修改；旧 build 128 IPA 保留。

## 首轮原生验收与基础设施修正
- cacbed8 设备编译抓到 BookDetailHero.swift:29 `ambiguous use of operator '-'`；已显式区分 CGFloat 几何与 Double 透明度，不把本地解析通过冒充编译通过。
- 200c949/iOS run 41422678298：native-tabs/job 125202035136 在 `simctl bootstatus` 的 180 秒预算超时，尚未进入产品测试；普通回归另行运行。日志保留同 HEAD 证据目录。
- 同 HEAD IPA run 41422678034/job 125201735050 被托管服务取消，check annotation 明确 `The job was not acquired by Runner of type hosted even after multiple attempts`，并报告 macOS arm64 capacity constraints；不是产品构建绿灯。
- 只为本分支将三项 CI 的 runner 路由切到官方标准 Intel 标签；其它分支仍用原标签，SDK、完整测试、断言、启动预算不变。不是跳过失败测试。标签及 Xcode 安装表已查 GitHub 官方文档。
- 复核补上两处一致性：标题单独选内置/导入字体时也发送缓存 @font-face 给 WebContent；页面实际绘制与分页测量均传递同一页眉字号/顶部间距。新增断言，不放宽旧断言。
- 本地检查仅为 25 个 Swift 文件无新增解析错误、git diff --check、CI 辅助脚本 py_compile 与 YAML 解析；最终本 HEAD 原生结果未出前不交付 build 129 IPA，不称真机/FPS 已通过。
- 首次加载封面或回落到主题占位时，文字语义和底色同帧落位，不单独慢慢把白底变暗而提前显示白字；仅已有封面色之间允许背景缓变，减少动态设置仍优先。新增取色首次载入/回落动画策略断言。
- 最后一次全量本地解析覆盖 27 个本轮 Swift 文件：ReaderRecovery119Tests 存在与 63aaff6 相同的既有解析器限制（第 361 行 `!`），新增语法错误为 0；不将 tree-sitter 当作 Apple 编译器。

## 本轮文件清单（ad81491）

- `D:/Gemini反重力/SourceReadSwift2/.github/workflows/ios.yml`
- `D:/Gemini反重力/SourceReadSwift2/.github/workflows/unsigned-ipa.yml`
- `D:/Gemini反重力/SourceReadSwift2/CHANGELOG.md`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/App/RootTabView.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Core/Storage/CustomFontManager.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Core/Storage/FontImportPolicy.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Bookshelf/BookshelfView.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Bookshelf/CoverToneSampler.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Bookshelf/ReadingHeroCard.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Discover/BookDetailHero.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Discover/BookDetailView.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Reader/CoverPageReaderView.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Reader/ReaderAutomationPolicy.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Reader/ReaderHeadingPreferences.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Reader/ReaderPageGeometry.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Reader/ReaderScrollChapterHeader.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Reader/ReaderView.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Reader/WebReaderDocument.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Reader/WebScrollReaderView.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Settings/AppearanceSettingsView.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Features/Settings/CustomFontManagementView.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Shared/DesignSystem/AppMotion.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Shared/DesignSystem/AppTheme.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Shared/DesignSystem/AppThemeOrnament.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Shared/DesignSystem/AppThemeSurface.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Shared/DesignSystem/AppVisualTheme.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Shared/DesignSystem/CoverAtmosphere.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwift/Shared/DesignSystem/LegacyTabBar.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwiftTests/ReaderRecovery119Tests.swift`
- `D:/Gemini反重力/SourceReadSwift2/SourceReadSwiftTests/Release117MotionSystemTests.swift`
- `D:/Gemini反重力/SourceReadSwift2/docs/adr/0117-system-owned-motion.md`
- `D:/Gemini反重力/SourceReadSwift2/docs/release-1.1.7/MOTION-SYSTEM.md`
- `D:/Gemini反重力/SourceReadSwift2/project.yml`
- `D:/Gemini反重力/SourceReadSwift2/scripts/reader_motion_ci.py`

## CI monitoring / Desktop test-candidate delivery · 2026-11-02
- User requested monitoring and Desktop download only; no app source changes, new commits/pushes, installation or signing were performed. HEAD remains ad814912685b53ce7c4b4262598e047c168bec55.
- Delivered C:/Users/Edc21/Desktop/SourceReadSwift-1.1.7-build129-ad81491-unsigned-UNVERIFIED.ipa (26510985 bytes), SHA256 44827ddb73b409a899dd382c71b70ecdcda1ab47ed832fc9e4fa0d520ce82f9a. Exact-head packaging provenance, ZIP CRC, com.edc21.SourceReadSwift / 1.1.7 / 129 / iOS16, arm64 iPhoneOS, bundled fonts and post-copy hash verified. Unsigned, user signing required. Previous Desktop IPAs preserved.
- Failed test evidence retained under F:/SourceReadSwift/reader-motion-117/ad814912685b53ce7c4b4262598e047c168bec55/. See ci-status.json, IPA_VERIFICATION.json, job-125214553115.log and job-125214553574.log. New motion tests and pan geometry test passed on native26, but this does not override overall CI failure or constitute FPS/physical-device acceptance.
- Next engineering work (not performed in this monitoring task): reconcile exact new theme identities/geometry expectations in Release116VisualTests without weakening coverage; reproduce WebKit testWebScrollRestoresAndReportsInsideOneLongParagraph failures at lines 84–85 before deciding app vs harness fix. Keep failing logs and rerun full exact-head gates after any fix.
