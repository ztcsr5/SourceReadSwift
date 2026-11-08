# REX 参考动效与两份 SwiftUI 原型审查

**结论：视觉方向可行，可以融入纸间；两份代码均不能原样合入。建议以 MotionLab 作独立实验底座，从 Gemini 版提取少量造型/数学思路，产品的数据、阅读器、导航与主题仍由现有模块负责。**

审查日期：2026-11-02（Asia/Shanghai）。产品基线 HEAD：`89c9a5148d6eeabe4f60af1ff6af1430056413c5`。本轮只新增审查文档和只读复核脚本，不改产品 Swift、项目配置或 CI，不执行附件中的实施指令。用户已明确授权 REX **静态 UI 研究**；没有启动、修改、解密或安装 REX，没有将其图片、Logo、着色器或私有代码移入纸间。

## 1. 实际检查了什么

| 材料 | 事实与边界 |
|---|---|
| 微信录屏 | 78.6 s，592 × 1280，HEVC；沿完整时间轴抽帧检查，包括尾段实际主页/空统计页。不是仅凭两份模型的文字描述。录屏编码帧率不等于 App 的运行帧率。 |
| Gemini 粘贴代码 | 3,826 行、188,990 bytes；含两套根 View、演示书籍/票根/统计、模拟书源和 LAN/TTS 界面，不是正式阅读器补丁。 |
| MotionLab ZIP | 31 个条目、11 个 Swift 文件、6 张书封及图标等；CRC、源文件引用、8 个资源清单文件和 scheme 目标引用检查通过。没有附带 shell build phase。 |
| 两个 MD | 与 ZIP 中的说明方向一致，承认未做 Apple SDK 构建。`CODEX_PROMPT.md` 中“立即开始实施”是被审查的附件文字，不是本轮执行授权。 |
| REX IPA | 137,535,128 bytes，953 个归档条目；Info.plist 自报 Rex 1.0.2/build4、最低 iOS 17；主程序 arm64 Mach-O/Swift，已剥离符号。 |

证据根目录：`F:/SourceReadSwift/release-1.1.7/motion-review`。`input-manifest.json` 记录输入 SHA256；`video-frames` 保存时间轴抽帧；`rex-static/INVENTORY.json`、`r2-ui-metadata.json` 保存包和二进制元信息；`static-findings.json`、`syntax-audit.json`、`project-checks.json` 保存静态检查。

### 视频给出的两个重要校正

- 约 25–29 s 的票根、34–38 s 的进度/资源环绕、42–46 s 的统计展示值得借鉴；核心是分层、节奏、遮挡、连续性，不是把所有卡片加同一层毛玻璃。
- 约 72 s 的真实“我的”页面是 **0.0 小时 / 无观看记录**，75 s 的资源库也是空态。引导页的 4.9 小时等数字只是展示素材，不能照搬为用户真实统计。

### REX 静态信息能证明和不能证明的内容

链接库同时包含 UIKit、SwiftUI、QuartzCore、CoreImage、Metal 等。字符串/类型元数据可见 `RexOnboardingViewController`、`RexOnboardingContinuousDepthModel`、`RexOnboardingFloatingPosterFieldView`、`RexOnboardingWatchlistPrinterView`、`RexOnboardingOrbitView`、`RexOnboardingStatsRollView` 等独立组件。**这些是架构线索，支持“专门的动效模块和状态编排”这一判断；不能据此断言具体算法、弹簧参数、GPU 开销或帧率。**

样本元数据还自报 `iphoneos27.1`，归档含 `hwpatch.dylib`。只记录观察，不推断其用途，不将此样本当作已验证的官方原始包，也不据此要求纸间提高最低系统版本。本轮没有逐函数恢复其实现或研究许可/鉴权逻辑。

## 2. 两份代码的审查结论

### Gemini：可以取视觉片段，不能当“完整连接版”

| 级别 | 决定性证据 | 问题 / 必要修改 |
|---|---|---|
| 阻断 | `GeminiPrototype.swift:3274–3282` 用 `Int.random(in: 28...135)` 生成延迟；3332/3337 固定 LAN 地址；1470–1479 仅切换朗读布尔值 | “并发校验 / 服务运行中 / 已激活”不是网络服务或 TTS 的实现。只可保留为明确标注的演示；产品必须连接已有真实服务与状态。 |
| 阻断 | 全文无 UserDefaults、AppStorage、文件持久化或编码器；书籍/票根主要是 `@State`，数据包含固定评分、日期、进度、4.9 h、5000 h 和公式热力格 | 不能替换书架、阅读位置、书签、统计存储。演示数据不能通过 adapter 混入生产。 |
| P1 | `:727` 为 `for i in 1...min(3, tickets.count)` | 清空票根再回放到第 3 步时会构造 `1...0`，存在确定的静态崩溃路径，未在本机原生运行触发。改用安全半开区间或集合 indices，并为 0 张票根提供演示/空态。 |
| P1 | `:320` 强制 `.dark`；多处硬编码白字、暗底和材质 | 与现有系统跟随、六主题及无障碍不兼容。复用 AppTheme/AppThemeSurface，不能统一强制暗色。 |
| P1 | `:576/:799` 局部 TimelineView；`:728/:835/:838` 不可取消的 asyncAfter；没有减少动态效果/场景状态策略 | 引导需可取消、可重入、离开即停止；旧步骤不能延迟弹票/震动或改新步骤状态。普通首页/阅读中不放无限装饰时钟。 |
| P2 | `:3535` 根容器把已有整页 ScrollView 再套进外层 ScrollView；模块配置有 m_reading/m_grid，但渲染 switch 没有对应分支 | 滚动归属与模块开关并未真正建模。将模块做成不带外层滚动的展示组件，由单一页面负责滚动和布局。 |
| P2 | `:354–390` 只是根据 step 改色的模糊圆；`:2391–2470` 是拖动视差；`:2681–2730` 是普通共享选中块 | 并未实现真正的 MeshGradient、陀螺仪或专门的果冻形变。效果可重做，但不能因名称就声称具备这些能力。 |

票根轮廓 `TicketStubShape`、有界拖动透视的数学、轨道的深度排序和局部 spring 节奏可以作为参考。不要将整份 3,826 行代码粘到 App 入口，也不要保留假书源、假服务和演示排行。

### MotionLab：更适合作为独立实验工程，但并非可上线组件库

| 级别 | 决定性证据 | 问题 / 必要修改 |
|---|---|---|
| 阻断 | 自带 `@main`，且有 ReaderView、BookDetailView、SettingsView 等与现有项目同名类型；工程最低 iOS 17 | 只能先作为独立 target/实验工程验证，不能整包拖进纸间 target。纸间仍保留 iOS 16；迁移时只抽组件，处理命名和系统门槛。 |
| P1 | `ZhijianMotionLabApp.swift:12` `.preferredColorScheme(.light)`；DesignSystem 大量固定浅色 | 与其验收目标中的系统明暗适配不符。必须移除强制浅色并映射现有主题 token，不引入第二套四主题持久化。 |
| P1 | `Models.swift:117–122` 使用 `(chapterIndex + 0.4)/chapterCount`，并对进度取历史最大值；ReaderView 只存章节、不存段落/UTF-16 锚点 | 不是精确阅读进度/位置，读到末章也不代表完成正文。产品直接复用已有位置模型和 ReaderGateway；不要让演示 reader 接管正式阅读。 |
| P1 | `Models.swift:102–133` begin/end 使用 Date 计总时长；全部 11 个 Swift 文件没有 scenePhase | 只有正常关闭时提交，后台停留可能计入、异常退出可能漏记，无法产生每日/每小时事件。修复实验记录口径；正式统计另走会话账本。 |
| P1 风险，待原生复现 | Home/Shelf 保留源封面，Detail 的 `isSource:false` 目标放在覆盖层；RootScene 的选中状态控制覆盖层而非系统导航 | 有几何关联不等于完成可交互 Hero 导航。必须检查双封面、目标落位、源滚出屏幕、连续开关、返回中断和 VoiceOver 访问下层页面等情况；当前不能承诺“一镜到底”。 |
| P2 | `HomeView.swift:183` 关闭沉浸背景时把 blur 从 45 改为 100 | 关闭开关并没有移除图像模糊绘制；不能当作性能降级策略。关闭时直接分支到静态主题面，不创建该背景层。未测量前不宣称一定卡顿或关闭后一定更慢。 |
| P2 | OnboardingView 有 `.id(page)`、opacity/scale 转场，没有共享元素；只做三页 | 是三阶段演示，不是 Gemini 描述的五步封面重排/出票/环绕/统计连续变形。缺失部分需单独设计，不是改几个参数即可完成。 |
| P2 | RootScene `.id(selection)` 重建页面；float 只在 onAppear 判断 reduced；toast 的独立 Task 不带身份；Settings 主题切换动画无 reduced 判断 | 需保留导航/筛选/滚动状态，支持运行中切换减少动态效果，使用可取消且有代际标记的任务。不能靠换 id 重建全页制造转场。 |
| P2 | 多处 38/40 pt 图标操作、固定字号和单行缩字；无减少透明度的统一降级 | 迁移时至少 44 pt 命中区，使用可缩放文本与大字布局；语义 Button、可见焦点、VoiceOver 模态隔离；复用现有无障碍材质策略。 |

README 对“不是真实书源阅读器、未做 Xcode 编译”的边界声明是正确的；`IntegrationContracts.swift` 也明确只是未装配示意。书封原创是作者声明，本轮不验证素材权属。合入只使用自己的或明确许可的素材。

## 3. 设计建议中需要纠正的认识

- **不是“所有线性动画都要换成 spring”。** 点击、展开可用弹簧；匀速轨道适合恒速，背景呼吸适合缓入缓出；保留系统滚动的减速/回弹。0.55/0.82 是调试起点，不是所有交互的统一结论。
- **不是“毛玻璃层数越多越高级”。** 主视觉、内容卡、导航应有层级；不要给列表每一层再套材质/大 blur/阴影。现有 AppThemeSurface 已负责真实 iOS 26 和无障碍门槛，应继续复用。
- **App 内出票不等于驱动系统灵动岛。** 原型只是绘制一个黑胶囊和向下出现的卡片。应做有安全区的应用内书笺出口，而非冒充系统 UI。ActivityKit 是单独的系统活动能力，不是任意跨系统边界的动画画布。
- **matchedGeometryEffect 只关联几何，不负责导航、点击、显示隐藏与生命周期。** 其 source 所有权要明确，不要混用多条入口或索引 ID；对缺失源节点提供普通转场降级。
- **SwiftUI 与 Flutter 的透视矩阵不要混抄。** SwiftUI 优先使用 rotation3DEffect 的透视参数；不要直接照搬文案中的 m32/Matrix4 下标。
- **不强制把刚验收的横向卡改成占屏 42% 的竖向海报。** 最可逆方案是新增可选“沉浸式首页”样式，默认保留现有横向大封面与真实阅读位置；小屏仍要能发现书架/搜书入口。

## 4. iOS 能力门槛（已核对 Apple 文档平台元数据）

| 能力 | 最低 iOS | 纸间的落地方式 |
|---|---|---|
| matchedGeometryEffect | 14 | 16 可用，但只适合受控的同一渲染树；不能当作完整导航方案。 |
| 普通 spring、rotation3DEffect、Shape、Canvas / 渐变 | 纸间 16 基线可用 | 可作为共同的造型/静态降级基础，不需要提高最低系统。 |
| PhaseAnimator / KeyframeAnimator / scrollTransition | 17 | 仅在可用分支使用；16 用普通动画状态机/静态状态，必要交互不依赖动画。 |
| MeshGradient / 导航 zoom + matchedTransitionSource | 18 | 18+ 可用，16–17 保留现有导航或受控覆盖层；Mesh 不是实现柔和色场的必要条件。 |
| 当前 App 的原生玻璃和原生 Tab 策略 | 26，且编译器支持 | 不被 Demo 的全局 ultraThinMaterial 或四 Tab 根结构替换。 |

主要官方来源：[MeshGradient](https://developer.apple.com/documentation/swiftui/meshgradient)、[阶段与关键帧](https://developer.apple.com/documentation/swiftui/controlling-the-timing-and-movements-of-your-animations)、[matchedGeometryEffect](https://developer.apple.com/documentation/swiftui/view/matchedgeometryeffect(id:in:properties:anchor:issource:))、[ZoomNavigationTransition](https://developer.apple.com/documentation/swiftui/zoomnavigationtransition)、[场景生命周期](https://developer.apple.com/documentation/swiftui/scenephase)、[Live Activities 设计](https://developer.apple.com/design/human-interface-guidelines/live-activities)。Apple 文档 JSON 已保存在证据根目录 `apple-docs`，没有仅凭记忆猜 API。

## 5. 与当前纸间的对接边界

| 目标 | 复用的真实模块 | 不允许被演示替换的内容 |
|---|---|---|
| 主视觉、柔和色场、轻视差 | BookshelfView、ReadingHeroCard、CoverToneSampler、AsyncBookCover/RemoteImageLoader | 最近书籍、未知进度/空封面、原有封面解析和缓存。不要新增一条重复下载链。现有取色已离主线程、有缓存；若增加模糊图，应后台预计算小图并有界缓存。 |
| 主题/材质/动效偏好 | AppTheme、AppVisualTheme、AppThemeSurface | 六主题与系统明暗模式；动效风格与配色主题正交，不迁移 Demo 的 zml.* 偏好。 |
| 底栏 | RootTabView、LegacyTabBar | iOS 26 的原生 TabView、16–25 的现有胶囊、迷你音频条和阅读时隐藏的 owner 机制。旧系统已具备 spring/共享选中块，无需推倒重做。 |
| 封面到详情 | 现有 BookshelfReaderGatewayView / BookDetailView 路由 | 真实书籍 ID、来源、返回栈、取消语义；先增强详情转场，不直接把长正文挂到 Hero 动画树上。 |
| 书笺票根 | ReaderBookmark、QuoteCardView、已有分享渲染 | 用户真实选择/保存的片段和章节定位；不从 Demo 固定 paragraphs[2] 或预置他人摘句制造记录。 |
| Bento 统计 | ReadingStatsSummary、BookshelfStore、ReadingHistoryStore | 先补真实会话数据与口径，再做图；不能把最后阅读日当完整历史。 |

### 当前项目自身的统计前置缺口（需要独立修复，不属于本轮 UI 修改）

`SourceReadSwift/Core/Models/ReadingStatsSummary.swift:62–66,77–82` 按 book.lastReadAt 的日期，把该书 **累计 totalReadingSeconds** 全部加到一天。反例：同一本书昨天读 3,600 s、今天读 60 s，当前公式会把今日算成 3,660 s，而不是真实的 60 s；昨日也失去这本书的记录。连续天数同样只看最后阅读日，无法恢复每天行为。

因此现有总时长可以作为历史累计，但不能直接生成可信的今日小时柱、近 7 天趋势、月度热力图。建议新增可去重的会话事件账本，存 UTC 起止/有效时长/书籍身份，展示时按用户时区分桶、跨午夜拆分；静默阅读只计有效前台，后台有声按明确口径另记。旧累计不伪造回填每天，历史缺失显示未知。需覆盖后台切换、跨天/时区、崩溃恢复、重复提交、旧记录兼容等测试。

## 6. 建议实施顺序与可判定验收

1. **隔离实验验证**：修复 MotionLab 的上述确定问题，在独立 target 下做真实 Xcode build 和交互验证；不从附件直接执行任何脚本。完成标准是小屏/普通屏、空数据、系统明暗/大字/减少动态效果均能走通，不是语法树无错误。
2. **可选首页视觉**：新增可关闭的沉浸样式，先接现有真实书籍/缓存/主题和打开阅读动作。完成标准是关闭后回到原横向卡，空书架/空封面/超长标题正常，取色和模糊不在主线程重复计算。
3. **独立书笺出票 + 详情连续转场**：复用真实书签/分享操作，票根有唯一消息身份、可取消动画；对详情入口使用稳定来源身份和 source/destination 管理。完成标准是连续保存/快速开关/返回中断、源被筛除、VoiceOver 和减少动态效果无丢内容/错误定位。
4. **引导页编排**：再做有限时长的封面墙、重排、出票、环绕。无真实书籍/票根时使用明确标识的原创演示，不写入书架或统计。完成标准是可跳过/回放、退后台暂停、离开无旧步骤回调，普通阅读无持续装饰动画。
5. **真实账本之后做 Bento**：先修数据口径并加回归，再做图表。没有数据保持空态；先不做不存在的全网推荐、评分服务或题材排行。

每次只接一个视觉变量，保留原首页。Instruments 验证冷启动、主线程、内存、GPU/过度绘制、滚动和转场；覆盖低电量、减少透明度、对比度和低分辨率图片。不从录屏或 static analysis 宣称 60/120 fps 达标。

## 7. 本轮验证与未运行项目

- 已运行：归档 CRC、输入 SHA256、11 个 Swift 工程引用、8 个资源清单、scheme 引用、授权样本的静态包/二进制信息、11 条源码事实/数学反例复核、git diff --check。
- Swift tree-sitter：Gemini 无语法树 ERROR；MotionLab 的 Models.swift:84/85 有 4 个告警，集中在 `as? [String: ...] ?? [字典]`。最小化后，仅给类型转换加括号即可消失，指向解析器限制；**不将其认定为已证实的 Swift 编译错误，也不把其他文件的解析通过当类型检查通过**。
- **未运行**：MotionLab/Gemini 的 Apple SDK 编译、模拟器交互、真实 Hero/手势/无障碍、Instruments。当前 Windows 主机没有 xcodebuild/Apple SDK；未为本轮审查向原仓库推送新的 CI 或安装依赖。已有 89c9a51 的原生全绿结果只覆盖现有纸间，不覆盖附件工程。

复核命令（不会运行附件代码）：

```powershell
Set-Location 'D:\Gemini反重力\SourceReadSwift2'
python -X utf8 scripts/review_motion_inputs.py --evidence-root 'F:/SourceReadSwift/release-1.1.7/motion-review'
git diff --check
```

预期：`PASS static evidence replay`，6 个输入哈希、11 个 Swift 引用、8 个资源清单、11 条源码事实/反例；native_build 明确 NOT RUN。

独立工程后续在 macOS 的构建命令（**本轮未执行，不是通过声明**）：

```bash
xcodebuild -project ZhijianMotionLab.xcodeproj -scheme ZhijianMotionLab \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## 8. 影响面与回滚

本轮新增 `docs/release-1.1.7/MOTION-REVIEW.md` 与 `scripts/review_motion_inputs.py`；证据和解包副本只在 F:。未修改输入原件、产品代码、既有未提交修改、阅读数据、签名或构建产物。无需迁移，原 IPA 不变，未执行回滚。

若仅撤销本轮仓库审查交付，删除下面两个明确的新文件即可（**未执行**，不删除证据目录或任何既有修改）：

```powershell
Remove-Item -LiteralPath 'D:\Gemini反重力\SourceReadSwift2\docs\release-1.1.7\MOTION-REVIEW.md', 'D:\Gemini反重力\SourceReadSwift2\scripts\review_motion_inputs.py'
```
