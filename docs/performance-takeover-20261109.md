# 动态帧率接管与渲染选型 · 2026-11-09

## 当前范围与检查点

- 最新优先级：定位交互期间掉帧；用户提出通过投屏/USB 交由助手取证。已接通 iPhone 13 Pro USB 开发服务，详见下方 USB 检查点。此前参考 App 与首屏几何查询修正均不能证明动态 120 Hz 问题已解决。
- 最新交互约定：用户自行操作手机，助手只监控；已用 egolite `handOff()` 归还浏览器控制，不再发送点击/滑动。已完成一轮用户确认开始的仅 Tab 切换采集，等用户提供该轮 App 内报告后对照。不要重复索取已收到的混合操作报告。
- 进书慢检查点：用户确认第一次打开与刚退出马上重进都慢且差不多。已从参考 App 研究转回纸间开场关键路径，只修复一项可复现开销：首屏/书签定位不再逐段测量全窗口。1200 段浏览器夹具中几何查询从 1213 次降到 21/22 次，位置正确；这不是毫秒耗时或真机帧率结论。尚未提交、推送、生成新 IPA。
- 益达复核补充：原 IPA 与解包的四个主要二进制逐字节一致，整理包 29 项通过。Flutter.framework 内嵌 Dart `3.12.0-239.0.dev`（2026-03-11），引擎 SDK 18.2；不能用 App plist 的 SDK 17.5 推断所有引擎组件古老。App AOT 只有一个 arm64 切片，已保留分析副本；标准 Blutter 当前仅支持 Android arm64 ELF，未展开 iOS AOT 完整调用链。详见 `docs/yida-renderer-evidence-20261109.md`，现阶段选型建议不变。
- 最新选型检查点：用户提供 Booku 2.0.0 的完整/深度解包，确认特别流畅的书是 EPUB，并报告帧率检测有 120 Hz。已独立确认应用接入 Readium → WKWebView 的 EPUB 路径、300 ms 页数通知防抖和 JS 进度合帧。决定先保留 WKWebView；下面早期 TextKit 2 对照建议不是已批准迁移。详见 `docs/booku-renderer-evidence-20261109.md`。
- 正式渲染器迁移尚未决定；先取当前实现的动态帧时间证据，不继续扩展 A 批或主题改造。
- 真机：iPhone 13 Pro，用户报告 iOS 27.0.1；安装包可能是 `161d555030f19d9d9774d38b6a2f993bc71f2b1f`，尚未确认。
- 用户实测：静止 120，轻动约 100，切 Tab 60–80，正常滑动 100–120，卡点约 60。测量工具仍未确认。
- 分支 `codex/perf-120hz-1109`，接管 HEAD `b10982da`。本次改动未提交、未推送、未打新 IPA。
- 旧完整验证 run `42565824202` / `0d160f9f` 已失败：两套系统均因 `ChapterCacheWriterPerformanceTests.swift:18` 引用不存在的 `$entries` 而不能编译。相同 SHA 的 IPA run `42565814394` 成功不代表测试通过。

## 复现与本地修正

1. 滚动中 metrics 失效后，`reportVisiblePosition` 直接返回，位置可持续停在旧段落。
2. 同一状态下 `captureAnchor` 复用上次上报段落；快速移动后该段落已不在视口，恢复可跳回去。1200 段浏览器夹具复现：248049 → 3258 px。
3. 改为在失效期间二分查找实时节点几何（O(log N)），保留当前位置/章标题/间隙语义，不重建整表。第一次几何查询仍可能触发布局，不能宣称零布局或已达到 120 帧。
4. 寻书页仍订阅每次书架进度变化并增加 `@State` revision；改成缓存成员集合，仅成员变化才更新，保留本地 URL 别名匹配。
5. 修正上述 CI 失败测试，使其验证当前约定：LRU touch 不发布 UI 变化，但内存排序与磁盘持久化必须一致。

改动文件：

- `SourceReadSwift/Features/Reader/WebReaderDocument.swift`
- `SourceReadSwift/Features/Discover/DiscoverView.swift`
- `SourceReadSwiftTests/ChapterCacheWriterPerformanceTests.swift`
- `SourceReadSwiftTests/Release117SearchProjectionTests.swift`
- `scripts/test_web_reader_visible_position.py`（函数签名提取同步，原断言不变）
- `scripts/test_reader_active_scroll.py`（新增）

## 验证边界

- 新增 3 项真实浏览器 DOM 用例先全部失败，修后全部通过：失效时连续滚动/反向位置、章标题与间隙、移动后锚点。
- 与既有可见位置及滚动锚点用例共 8 项通过。
- 4 个改动 Swift 文件相对 HEAD 无新增 tree-sitter 语法错误；`git diff --check` 通过。
- 未运行新的 iOS SDK 编译、原生 XCTest、iPhone 性能采样。浏览器测试只证明逻辑与几何查询数量，不证明 iOS WebKit 性能。

## 本轮首屏定位修正

现象：用户报告已读书退出后立即重进，与首次进入一样慢。检查当前代码确认 `makeWebView` 每次新建视图，加载 shell → 收到 bridge ready → 后台生成正文 JSON → 注入正文 → 定位 → 回报就绪 → 撤除遮罩；未建立这些步骤的真机耗时占比。

决定性证据：`resetScroll`、初次 `setContent` 位置回报和 `scrollToFlat.finish` 均调用默认会 `ensureMetrics` 的位置采样。1200 段真实 DOM 用例中，首屏和书签位置恢复均产生 1213 次 Element/Range 几何查询，且清空 dirty 标志，证明就绪依赖全表测量。用户可能安装的 `161d555` 源码也包含这三条无参数位置采样与 `ensureMetrics` 路径，但不能据此声称确认了实际安装包身份。

修法：在 `WebReaderDocument.swift` 的三个显式定位/开场回报点传入 `preciseOffset=true, allowMetricsRebuild=false`，复用前阶段的实时二分定位；保留精确字符位置、同步回报就绪和原来的闲时指标重建。首次几何查询仍可能触发 WebKit 布局；这项改动不消除 DOM 创建和 WebView 冷启动成本。

验证：新增两个浏览器回归用例先失败，再修后通过；首屏 21 次、保存字符位置 22 次几何查询，恢复目标段落/字符所在行正确。当前活动滚动 5 项、可见位置 2 项、滚动锚点 3 项、开场/跳转报告 5 项、章节到达 1 项，共 16 项通过。`git diff --check` 通过。Windows 没有 Xcode，未运行 iOS SDK 编译或真机性能采样。

在仓库根目录执行：

```powershell
python -B -X utf8 scripts/test_reader_active_scroll.py
python -B -X utf8 scripts/test_web_reader_visible_position.py
python -B -X utf8 scripts/test_reader_scroll_anchor.py
python -B -X utf8 scripts/test_reader_jump_reports.py
python -B -X utf8 scripts/test_reader_chapter_arrival.py
git diff --check
```

预期各脚本输出 `OK`，diff 检查无输出。本轮只改上述 3 处运行参数及一个解释注释，新增两个回归用例；无数据迁移。不应整体恢复该 Swift 文件，那会删掉前阶段修复。只撤销本轮运行逻辑的独立补丁命令：

```powershell
git apply --reverse 'C:\Users\Edc21\Documents\IOS\analysis\reader-opening\first-position.patch'
```

## 渲染选型：建议而非已迁移

- 益达 1.4.4 包 SHA-256：`283cf5bb7b6775c482294b6fc2acb22cd4e760275d2fef09d2c310f4123e8e0e`。
- 本次直接确认包内 `Flutter.framework`、`App.framework`、`rust_lib_yida.framework`；Info.plist 含 `CADisableMinimumFrameDurationOnPhone=true`，未见显式 Impeller 开关。
- 历史记录称发现 Impeller/Metal 字符串；Flutter 官方当前文档确认 iOS 使用 Impeller。具体旧包运行后端与正文调用路径未动态验证。
- 官方来源：https://docs.flutter.dev/perf/impeller
- TextKit 2 的 viewport 控制器布局可见区域及额外滚动区域：https://developer.apple.com/documentation/uikit/nstextviewportlayoutcontroller
- 建议先实现可回退的 TextKit 2 连续阅读对照面，保留 WKWebView。用相同正文、字号、图片、缓存状态比较进入、持续滚动、正反跨章与重开落点，再决定迁移。
- 不能直接回接旧 `NativeReaderTextView`：`rebuild` 在主线程替换整窗 attributedText 并 `ensureLayout` / `layoutIfNeeded`；这不是新的视口排版方案。
- TextKit 与 Impeller 不是同一层：前者是文字布局/渲染系统，后者是 Flutter 渲染引擎。TextKit 2 不保证 120 帧；换 Flutter 也可增量嵌入，但当前无证据值得承担混合框架成本。
- WKWebView 不会因每次滚动必然整页重排，跨进程本身也不能证明性能上限。切 Tab 的 SwiftUI/主线程问题须独立排查。
- CADisplayLink 请求频率不是屏幕实际刷新保证；当前 HUD 是回调节奏，不是 GPU 呈现统计。需要真机呈现/卡顿证据判断最终达标。

## 下一步

先利用已接通的 USB 服务复现切 Tab 和滚动卡点，将手机端回调、系统图形计数与操作时间对应。正式性能对照需关闭投屏，避免编码和触控桥影响结果。随后量化已缓存书进书的分段耗时（正文可用、WebView shell、正文挂载、定位与揭开遮罩）。保留迁移选项，不用参考 App 的流畅替当前实现背书。补真实 WebKit 用例与 Swift 编译，避免引用旧 SHA 的通过结果。不要改图标、主题或不相关备份文件。

## 动态帧率代码审核：尚未归因

- `FrameRateCoordinator.apply(to:)` 读取屏幕上限并记录 signpost；没有将 `preferredRange` 结果应用到窗口。不能沿用注释声称已设置 scene 帧率范围。
- `AppRefreshRateKeeper` 常驻最高频率请求的空 `CADisplayLink`；请求节奏不保证 App 内容按该频率完成呈现。
- `AppFrameProfiler`/HUD 测主线程 DisplayLink 回调节奏，不是 GPU 实际呈现帧率；诊断页将回调降低直接等同主线程/合成器掉帧的文案过度归因。
- 尚未新增卡顿与 Tab/正文更新/布局关联的诊断时间线，尚未更改上述帧率请求参数。不得称已完成该诊断实现或找到所有卡顿根因。

## USB 与投屏检查点 · 2026-11-09

- `pymobiledevice3 usbmux list --usb --simple` 返回 1 台 USB 设备；设备标识不写入本文件。
- `lockdown get --key ProductType/ProductVersion/BuildVersion` 实际分别返回 `iPhone14,2`、`27.0.1`、`24A446`；开发者模式查询为 true。
- WDA status 返回 `Failed to connect to service port.`，没有确认可用的 WebDriverAgent 通道。
- 初始未挂载开发镜像，显示服务访问失败。执行 `pymobiledevice3 mounter auto-mount --userspace` 下载 Cryptex1 DeveloperDiskImage，经 TSS 个性化后返回 `DeveloperDiskImage mounted successfully`。这是手机调试环境变化，未修改纸间安装包或 App 源码。
- 挂载后显示信息查询成功，主屏模式为 1170×2532、120 Hz。这里的模式信息不代表纸间实际每秒呈现 120 帧。
- `pymobiledevice3 developer dvt graphics --userspace` 有界采集 8 秒收到 7 条图形计数；首条 `CoreAnimationFramesPerSecond=0`，未结合前台 App 和操作归因，不作为纸间帧率结论。采集已结束。
- 已启动本机投屏服务：`pymobiledevice3 developer core-device display serve-web --userspace --bind 127.0.0.1 --http-port 18768 --no-audio`。根页面与 `/codec` 均 HTTP 200，服务收到 HEVC 编码参数并启动 HID worker。运行会话 1688，进程 PID 33296。未开放到局域网。
- 用户追问 120 Hz 投屏后，实际调用 `pymobiledevice3 developer core-device display get-media-stream-server-status --userspace`：视频会话 `connection.streamConfig.Framerate=60`，`CustomWidth=1184`、`CustomHeight=2544`；音频会话 Framerate=0。这确认当前协商视频帧率为 60 fps，不是 120 fps，也不证明持续实际传输能达到 60 fps。当前工具公开参数未提供帧率设置；不据此声称所有 iPhone 投屏方案均不支持 120 fps。手机主屏模式 120 Hz 与投屏编码帧率须区分。
- 此版本 `--no-audio` 只关闭浏览器默认音频播放；后台音频解码仍尝试启动并报 `AAC-ELD decode requires macOS (AudioToolbox)`。视频服务继续工作；未验证音频，不需要音频来排查阅读性能。
- 手机截图命令成功，原图位于 `C:\Users\Edc21\Documents\IOS\analysis\iphone-usb-20261109\connection.png`，尚未送模型查看。
- Windows 浏览器 Computer Use 被自动安全检查终止：无法可靠识别当前浏览器 URL 以执行策略检查。没有继续浏览器输入或绕过。用户可手动打开 `http://127.0.0.1:18768/`；实际浏览器解码画面和反向触控尚未验证。
- 停止本次投屏：`Stop-Process -Id 33296`（先核实该 PID 仍属于本次服务，避免 PID 重用误停其他进程）。开发镜像保留供下一次性能取证。

## egolite 与用户操作采集 · 2026-11-09

- 按 ego-browser 技能连接用户现有 task space 0 / page p1，URL 为本机投屏页面。浏览器实见解码画面及 13/54/57/60 fps 等瞬时投屏读数，不能视为纸间帧率；视频日志另有 4–8 秒重连记录。
- 浏览器点击设置后，USB 手机截图确认到达纸间设置页；点击控制通道成立。一次短拖动被识别为点击，误入 Web 写源页，随后发送关闭服务的点击；未独立确认最终开关状态。用户已要求停止助手操控，此后不再发送手机输入。
- 项目原 bundle PID 查询为 0；用户确认纸间使用改标识/容器环境。USB 查询确认 LiveContainer 3.8.0 运行，PID 38664，纸间画面与用户确认共同作为本轮宿主选择依据。未核实 guest 安装包 SHA，不能将宿主版本当作纸间版本。
- 证据目录：`C:\Users\Edc21\Documents\IOS\analysis\ego-reader-20261109`。浏览器轮次脚本在 `scripts/`，只运行本会话新写脚本；当前浏览器已交还用户。
- 第一轮 USB 采集 `capture-01`：UTC 07:53:05.786–07:54:09.393，120 条宿主样本、59 条图形样本。宿主 CPU 中位数 1.34%、峰值 2.67%；系统图形 FPS 值为 0/1/5/11/13，不能据此判断 App 呈现帧率。没有与用户报告对齐的起止时间，不进行因果对应。
- 用户提供混合操作报告（切 Tab、进退书、正文滚动都有）：3121 次 / 30.02 秒，平均 104.0 次/秒，P95/P99 9/45 ms，最慢 274.31 ms，超过参考间隔 133 次，估算调度缺口 479 次，低电量关→关、温度 0→0。保存在 `user-mixed-report.json`。报告证实长回调间隔尾部，不能独立证明 GPU 丢帧、主线程具体阻塞原因或应迁移 WKWebView。
- 用户回复“开始”后只切 Tab 的采集 `capture-tab-01`：UTC 08:10:41.842–08:11:21.854，74 条宿主样本；CPU 中位数 33.79%、峰值 80.18%，为工具的单核百分比标度。等待该轮 App 内报告。不要把高 CPU 本身视为卡顿根因。
- 调用栈通道先取得 5 条宿主栈（地址未符号化）。正式 Tab 轮默认 `--count=-1` 触发 `ValueError: Stop argument for islice() must be None or an integer: 0 <= x <= sys.maxsize.`，位于工具 `core_profile_session.py:407`；改显式 `--count 100000` 后重试。
- 栈重试 UTC 08:11:45.741 开始，得到 1033 条、线程 7177386，事件时间 16:11:47.486949–16:11:55.612614（工具格式），随后 `ValueError: 30 is not a valid AddressFamily` 导致解析失败。重试晚于主要 Tab 采样窗口，不能用于解释该轮具体卡点，也不是完整 30 秒调用栈。
- 栈重试原文件 `capture-tab-01/stacks-retry.txt`：569675 bytes，SHA-256 `d583ad45c143530a568a34dced61858e9c975490eb67afbb68fd422bc40c3502`。原始文件保留，未把大输出倒入聊天。符号与安装版本未匹配，尚未得出函数级根因。
- 两轮有界 USB 采集均已结束。当前保留投屏服务供用户操作；不自动恢复浏览器控制，不再修改手机设置。


## 接续检查点：先隔离合成成本，不切渲染器 · 2026-11-09 傍晚

用户当前报告：静止 120，轻动约 100，切 Tab 60–80，正常滑动 100–120，章节卡点约 60。用户正在思考是否切换渲染器。

先把已有证据摆在一起：

- 用户正在验证的 `161d5550` 早于当前分支 30 多个性能提交；当前 HEAD 已包含章节续接、书架投影缓存、阅读进度不再刷新所有 Tab、滚动中不做全表测量等修复。用旧包的体感直接推导“必须换渲染器”不成立。
- Booku 2.0.0 已独立确认走 Readium → WKWebView 的 EPUB 路径，用户观察到 120 Hz；益达走 Flutter/Impeller，也流畅。渲染器不是唯一变量。
- 用户混合操作报告是 3121 次回调 / 30.02 秒，平均 104.0 次/秒，P99 45 ms，最慢 274.31 ms。这个尾部更像主线程/合成提交掉期，而不是“渲染器上限只有 60”。
- 另一个未排除变量：纸间在 LiveContainer 3.8.0 中运行，益达是独立安装。容器注入与宿主 Info.plist 可能影响 ProMotion 行为，不能用两者直接对比。要得到干净的 120 Hz 结论，需要在正常安装（非 LiveContainer）的同一台 iPhone 上复测。

因此本轮不迁移 TextKit/Flutter。先做两件可回退的事：

1. `b304ef24 perf(reader): avoid layout work and offscreen redraws during motion`：滚动中 metrics 失效时用实时节点二分定位，不在 fling 中重建全表；首屏与书签定位显式关闭 metrics 重建；Discover 只缓存书架成员关系，不因阅读进度重绘离屏结果。
2. `ae7c3cc4 perf(app): add an isolation switch for glass and tab chrome`：开发者调试里新增“性能优先（关闭玻璃与系统 Tab 栏）”。开启后主题表面退回纸张、关闭卡片阴影、自绘 Tab 栏并用不透明表面；不改变默认设计。

HUD 现在同时显示两个数：`请求 N / 上限 M`。`请求` 是 `AppRefreshRateKeeper` 实际向系统申请的频率，`上限` 是屏幕 `maximumFramesPerSecond`。若请求是 120 而实时 Hz 仍掉到 60–80，问题在主线程/合成；若请求本身是 60，才是帧率申请失败。

### 一次安装后的对照顺序

1. 安装本轮 IPA，先在设置 → 诊断 → 开启开发者调试，打开全局帧率采样。
2. 默认设计下只切 Tab 30 秒，记录 HUD 的 `请求/上限`、实时 Hz、p99。
3. 打开“性能优先”，重启 App，再做同一组 Tab 切换。若 120 恢复，问题在玻璃/系统 Tab 栏；若不变，问题在 SwiftUI 主线程或 WebView 内容更新。
4. 关闭性能优先，进书只做同章连续滚动，记录章节边界前后的 HUD。

### 决策门槛

- 若性能优先后 Tab 切换稳定在 118–120，且 p99 ≤ 8.4 ms：保留性能优先或只移除对应玻璃层，不换渲染器。
- 若两种模式都掉，但纯正文滚动在章节追加前稳定、追加时掉：继续做 WebView 章节窗口/追加优化，必要时才做 TextKit 2 对照面。
- 若关闭玻璃、关闭所有阴影、纯文本无图片仍 P99 > 16 ms，并且换成独立安装后依旧：才进入渲染器迁移评估。迁移前必须保留 WKWebView 可回退路径，并用同一本书、同一字号、同一位置做 A/B。

本轮验证：5 个 WebReader 浏览器脚本、3 个滚动锚点脚本、5 个跳转报告脚本、1 个章节到达脚本全部 `OK`；`git diff --check` 通过；tree-sitter 语法审计对 15 个改动 Swift 文件无新增解析错误。iOS SDK 编译与真机仍以 CI/IPA 为准，尚未运行。
