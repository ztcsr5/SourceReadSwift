# 益达 1.4.4：报告复核与渲染选型边界

## 决定

保留纸间 WKWebView 的选型建议不变。益达证明了另一个技术体系可以有良好观感，但这份字符串计数报告没有证明阅读页的具体 widget 调用链，更没有证明纸间必须换 Flutter/TextKit 才能流畅。

当前不展开完整 Dart AOT 逆向。已完成单 arm64 切片提取，可供后续针对明确问题使用；“切片后直接跑标准 Blutter，钉到最后一行代码”不是已验证可行的方案。先解决纸间可重复的掉帧场景，比继续枚举参考 App 的框架更能推动当前目标。

## 已独立核实

- IPA：`C:\Users\Edc21\Downloads\yidaApp-1.4.4-release-nosign.ipa`，37,340,273 bytes，SHA-256 `283cf5bb7b6775c482294b6fc2acb22cd4e760275d2fef09d2c310f4123e8e0e`。
- 原样目录：`F:\dsh\workspace\default-workspace\yida\Payload\Runner.app`。
- 整理报告：`F:\dsh\workspace\default-workspace\yida\Yida_1.4.4-深度解包`，其校验脚本输出 `checked=29 bad=0 / ALL OK`。
- 原样目录的 Runner、App.framework/App、Flutter.framework/Flutter、rust_lib_yida.framework/rust_lib_yida 均与 IPA 对应文件逐字节一致。
- 身份：`com.xinqiu.yidaapp` / 是你的益达 / 1.4.4（build 1.4.4）。App plist 最低 iOS 13，SDK iphoneos17.5，Xcode 1540。
- App plist 中 `CADisableMinimumFrameDurationOnPhone=true`，没有 `FLTEnableImpeller` 键。
- Flutter.framework 内有 `Using the Impeller rendering backend (Metal).` 日志文本。这里是包内字符串，不是本次捕获到的运行日志。
- App.framework/App 的 FAT 头只有 **一个 arm64 切片**：偏移 16,384，长度 17,108,416 bytes；不是多个架构都需要拆。其 `cryptid=0`。
- 切片 SHA-256：`ccec2ee01087921b6855452a0d4a838089e5182564fc0a9d0fbb9bcd037ac64e`。

## “益达引擎很老”的判断需要修正

Flutter.framework 文件偏移 `0x7d8efd` 处直接读到：

```text
3.12.0-239.0.dev (dev) (Wed Mar 11 13:04:08 2026 -0700) on "ios_arm64"
```

这是内嵌 **Dart runtime 版本字符串**，不是已识别的完整 Flutter SDK 发布版本。引擎 Mach-O 的 `LC_BUILD_VERSION` 另记录 iOS SDK **18.2.0**，最低 iOS **13.0.0**。因此 App plist 的旧 Xcode/SDK 标签不能代表所有嵌入组件都用同一工具链，也不足以证明运行时古老。未据此推断 App 打包日期、是否替换过引擎或使用了哪个 Flutter 官方发行版。

用户观察的“没有玻璃效果、风格旧、很流畅”仍然有效，但它不能单独确定流畅原因。玻璃效果的成本需在纸间相同场景下独立关闭/开启对照，不能先认定是主因。

## 对报告的关键校正

| 原推断 | 目前能成立的结论 |
|---|---|
| 计数即证据 | 计数证明搜索命中，不能证明调用方、路径、线程、命中率或耗时 |
| TextKit 完全没接入 | 未检出相关名字只能作为线索，不能据此排除系统内部实现、动态调用或其他间接路径 |
| WKWebView 只用于登录/验证码 | 插件和规则文档证明存在这些用途；不能排除正文、内嵌内容或其他模式也使用 WebView |
| ParagraphBuilder/TextPainter 证明正文就是 RichText 或 CustomPaint | 这些是 Flutter 公共文本设施，错误消息也可能被打包。它们的存在不能定位益达阅读业务调用 |
| Impeller/Metal 字符串说明运行后端已实测 | 支持 Impeller/Metal 的静态证据明确，未捕获该样本真机启动后的后端日志 |
| Rust 只解析/解密，绝不画字 | 解析相关字符串证明能力线索；排除其他职责需要调用链与导出接口分析 |
| 翻页一定是 PageView | 没有已核实的 Dart 阅读页调用链，不能把常见 Flutter 实现方式当作事实 |
| FlutterView / WebContent 进程 / JS 桥三种方法均可直接自证 | 必须关联当前可见正文的具体视图实例和事件；隐藏浏览器、预热、平台视图嵌入及其他页面都可能干扰判断 |
| PDFKit 零命中就证明不支持 PDF | 至多说明当前搜索未检出该原生依赖，不排除 Flutter/第三方/网页方案 |

Flutter 的一般框架关系已经对照官方源码：`RichText.createRenderObject` 创建 `RenderParagraph`；后者持有 `TextPainter`；`TextPainter` 使用 `ui.ParagraphBuilder`。因此 RichText 和 ParagraphBuilder 不是互斥渲染路线。CustomPainter 也可能调用 TextPainter。该关系解释了为什么计数不能区分益达具体实现，**不是**用当前 Flutter 源码代替益达版本的反编译结果。

- <https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/basic.dart>
- <https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/rendering/paragraph.dart>
- <https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/painting/text_painter.dart>

## Blutter 适用性

2026-11-09 读取标准项目 <https://github.com/worawit/blutter> 的 README：

> Currently the application supports only Android libapp.so (arm64 only).

其待办中仍有 `Reading iOS binary`，并注明混淆应用仍缺少许多函数。本包是 iOS Mach-O；去掉 FAT 包装不会使其变成 Android ELF，也不会恢复 Dart 源码。若未来确需深入，应核验支持此 Mach-O 与 Dart snapshot 版本的工具或适配路线，不能照搬标准 Blutter 命令承诺成功。本轮未安装或尝试运行 Blutter。

## 复核命令与结果

```powershell
python -B -X utf8 'C:\Users\Edc21\Documents\IOS\analysis\yida-1.4.4\scripts\verify_yida_sample.py' --ipa 'C:\Users\Edc21\Downloads\yidaApp-1.4.4-release-nosign.ipa' --unpacked-root 'F:\dsh\workspace\default-workspace\yida' --output 'C:\Users\Edc21\Documents\IOS\analysis\yida-1.4.4\verified'
```

实际输出：

```text
PASS: IPA identity and 4 unpacked binaries match; one arm64 AOT slice extracted
Dart runtime: 3.12.0-239.0.dev (dev) (Wed Mar 11 13:04:08 2026 -0700) on "ios_arm64"
Flutter engine build: {'platform': 2, 'minimum_os': '13.0.0', 'sdk': '18.2.0'}
```

输出 `verified/verified-evidence.json` 与 `verified/App.arm64`；脚本仅使用 Python 标准库，未安装依赖。未运行益达、真机 View Debugger、帧率采样或完整 Dart/Rust 调用链恢复。

影响与回滚：只新增本报告、本地分析脚本/副本，并补充接管记录；原 IPA、用户解包目录及纸间运行代码未修改。撤销本轮只需删除上述新增记录/分析目录并移除接管记录中的益达补充；保留此前未提交修复。
