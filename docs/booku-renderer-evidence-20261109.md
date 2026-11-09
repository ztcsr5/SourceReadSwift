# Booku 2.0.0：EPUB 渲染证据与纸间选型

## 当前决定

先保留纸间的 WKWebView，暂停全面迁移 TextKit 或 Flutter。TextKit 2 仍可作为未来对照实验，不是已经确定的解决方案。

用户确认，在 Booku 中观察到特别流畅的阅读对象是 **EPUB**，并报告肉眼与帧率检测可见 120 Hz。不能用“缺少 plist 高刷开关”把这项观察改写成“实际只有 60 fps”。本次没有真机呈现帧率采样，也没有证明纸间已达到 120 fps。

Booku 包中已确认存在应用接入的 **Readium → WKWebView EPUB 显示路径**。Readium 是 EPUB 阅读框架，WKWebView 是该路径使用的 Web 内容视图；两者不是互斥选项。仅凭 WKWebView 这个名称无法解释两个 App 的流畅度差异。

## 样本身份与一致性

- 原包：`C:\Users\Edc21\Desktop\Booku_2.0.0-完整解包\Payload\AiReader.app`。
- 整理包：`F:\dsh\workspace\default-workspace\booku\Booku_2.0.0-深度解包`。
- 主程序 `AiReader`：65,147,520 bytes；SHA-256 `b0190fe42fd7ada3525625c0a521d1f233bd0446ec2187b32fa225c5dbdf4815`。
- plist：`TZAL.AiReader`，Booku 2.0.0（29），最低 iOS 17.0，SDK iphoneos26.2；不存在 `CADisableMinimumFrameDurationOnPhone` 键。
- Mach-O：arm64，`LC_ENCRYPTION_INFO_64.cryptid=0`。
- 两个已有校验脚本分别输出 `checked=161 bad=0` 和 `checked=107 bad=0`。
- 原包与整理包的 `Info.plist`、`readium-reflowable.js`、`readium-fixed.js` SHA-256 相同。
- 可重排 JS：94,970 bytes，SHA-256 `f5edf5e65b01ea869ebb0c4ce3cf6cf4556956bf387aef58c513bd2cb343176b`。
- 固定版式 JS：94,603 bytes，SHA-256 `a0e895ded02ee7a43be199ffcd23e8302501c3d8c6f4e6755828c6d2da98f807`。

## 独立核实的实现证据

本次不只读取 dsh 报告：直接解析原包 plist、Mach-O 加载命令、Swift 字段元数据、Objective-C 类/方法信息，并定向反汇编。IDA 启动脚本返回 `ERR:IDADIR not set and IDA Pro not found. Set IDADIR environment variable.`，未完成 IDA 分析；随后使用本机 radare2 5.9.8 与 Capstone。未安装额外依赖。

以下地址均为此 SHA 的静态虚拟地址，不能直接当作真机 ASLR 后地址。

| 证据点 | 实际观察 | 可得结论 |
|---|---|---|
| 应用宿主 | `ReadiumEPUBReaderHostViewController.navigator` 的 Swift 字段类型解析为 `EPUBNavigatorViewController`；`0x1014fdd90` 起读取该字段，调用 `addChildViewController:`，取其 view 并添加 | 应用确实接入 Readium EPUB 控制器，不只是残留第三方库名称 |
| 正文视图 | `EPUBSpreadView.webView` 字段类型解析为 `WebView`；Objective-C 类 `ReadiumNavigator.WebView` 的父类是 `WKWebView` | Readium 的正文视图属于 WebKit 路径 |
| 视图创建 | `0x102e0c340` 读取 `WKWebViewConfiguration`，后续 `initWithFrame:configuration:` 的返回对象在 `0x102e0c470` 写入 `EPUBSpreadView.webView` | 有实际创建并保存 Web 视图的代码 |
| 滚动通知 | `EPUBReflowableSpreadView.scrollViewDidScroll:` 位于 `0x102e08668`；取消已有 `notifyPagesDidChange` 请求，然后以 double 常量 0.3 调用 `performSelector:withObject:afterDelay:` | 页数变化通知采用 300 ms 延迟/防抖；不是把整个滚动或所有任务延迟 |
| JS 进度 | 原包脚本把 `scroll` 绑定到函数 `w`；其中 `progressionChanged.postMessage` 由待处理标志保护，放在 `requestAnimationFrame` 回调内 | 进度消息按动画帧合并；不代表几何计算和全部滚动工作均被合并 |
| JS 尺寸 | 原包存在 `new ResizeObserver`，回调先取消已排队 animation frame，再排新 frame | 这一条尺寸变化处理路径合并调度 |
| 翻页相关结构 | Readium 自身有 `PaginationView`，包含 `scrollView`、`loadedViews`、前后预载数量字段；应用另有 `ReaderPageCurlContainer` | 不能把整包所有 EPUB 翻页统一归为 UIPageViewController/pageCurl |

静态包还存在 `ReaderEPUBCompatibilityModeStore`、原生页面布局、开场覆盖层、快照遮罩等结构。**没有动态追踪用户当时的模式和分支，不能声称所有 EPUB、所有翻页模式、整个动画的每一帧都只有 WKWebView。** 当前证据足以否定“发现 CoreText 就说明 EPUB 已全面绕开 WebKit”的推断。

## 对上一份流畅原因报告的校正

| 原说法 | 校正后的证据边界 |
|---|---|
| 没有高刷键和 CAFrameRateRange，所以只有稳定 60 fps | 不成立。键缺失已确认；系统动画、显示回调和最终内容呈现需区分。不能凭未找到结构体名推导刷新率，也不能据此否定用户报告的 120 Hz |
| 全书预分页落盘，所以翻页零排版开销 | 服务/仓储/缓存类型证明有相关实现线索；没有验证所有模式的命中率、失效策略与翻页耗时。TXT 服务更不能直接解释用户测试的 EPUB |
| Task/async 数量证明重活全在后台 | 不成立。Task 可继承 actor 上下文，async 也不等于后台执行；须追踪执行器及实际调用并采样主线程 |
| CoreText 直接出帧、绕过 UILabel，所以流畅 | CoreText 导入包括排版 API 和 CTLineDraw；创建 CTFrame/取得文本范围不等于屏幕绘制。未证明这些调用属于用户测试的 EPUB 主显示路径，更未量化其收益 |
| TextKit 2 只用于编辑态 | 未证实。包内还有 LayoutPageViewTK2，不能仅凭 NSTextLayoutManager 名字限定用途 |
| 打开动画期间已经完成排版 | OpeningPacket/Layout 类型是机制线索，不能证明具体执行时段和完成时点 |
| 所有背景图按尺寸降采样，且不在主线程解码 | 缩略图 API 和缓存存在不等于所有图片都经过该路径；还缺调用参数、调用方和线程证据 |
| ResizeObserver 出现 10 次、rAF 5 次，所以所有回调都合帧 | 出现次数可能含 polyfill 和无关功能。已确认特定 ResizeObserver 回调与进度消息合帧，不能扩展为全部回调 |
| Canvas 只画图形且一次绘制 | 类型名不能证明重绘频率、绘制成本或没有其他视图参与 |
| 打包 PDF/CBZ/Audio 导航类就说明产品全部使用这些渲染器 | 只能列为包内能力，用户入口、路由与实际支持情况未核实 |

Apple 官方资料：<https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays>。

本次已读取官方 JSON。文档同时说明：部分框架自动管理帧节奏；自定义 CADisplayLink/CAAnimation 帧率提示需要遵守 plist 配置要求；系统决定最终刷新节奏，不能强制某个值。因此不能简化成“缺键必然全 App 60”，也不能反过来宣称这个键毫无作用。Booku 的具体 120 Hz 场景尚未独立复测。

## 对纸间的下一步

1. 先保留 WKWebView，检查滚动热路径、跨章布局和 SwiftUI 刷新工作量；用一次可重复的卡点场景验证一个改动。
2. 切 Tab、进退书与正文滚动分别归因。换正文布局系统不会自动消除主页或根视图的重复计算。
3. 如果真机采样证明正文布局确实是剩余瓶颈，再做同文档、同模式、同缓存状态的 TextKit 2 对照；以呈现卡顿与正确性决定迁移。

预热、页面复用、限制滚动期间工作量值得对照；目前它们是优化方向，不是纸间根因已经确定。无需现在全盘引入 Readium；它适合 EPUB 文档能力，纸间现有正文来源与功能约束需要单独评估。

## 复核与产物

本地研究目录：`C:\Users\Edc21\Documents\IOS\analysis\booku-2.0.0`。内有主程序分析副本、类清单、重定位、定向反汇编和官方文档缓存；没有修改用户两个解包目录。

可重复核验命令（PowerShell）：

```powershell
python -B -X utf8 'C:\Users\Edc21\Documents\IOS\analysis\booku-2.0.0\scripts\verify_epub_evidence.py' --app-root 'C:\Users\Edc21\Desktop\Booku_2.0.0-完整解包\Payload\AiReader.app' --output 'C:\Users\Edc21\Documents\IOS\analysis\booku-2.0.0\verified'
```

实际输出：`PASS: binary identity, Swift field types, native call sites, 0.3 s notification delay, JS coalescing`。

该命令校验固定样本 SHA，复核字段类型、原生调用点和脚本行为，并导出 `verified-evidence.json`、`verified-functions.txt`。静态证据核验不是 iOS 性能测试。本轮未运行 Xcode、iOS XCTest、真机 Instruments；未提交、推送或制作 IPA。

影响与回滚：本轮只新增研究记录、分析产物并更新接管状态，不变更纸间运行逻辑。删除本次研究文档/分析目录并移除状态文件的本次补充即可撤销记录；不要回滚上一阶段尚未提交的修复。
